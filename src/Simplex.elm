module Simplex exposing
    ( new
    , zeroDowntimeMigration
    , BackendProgram(..), ModelMigrationContext, MsgMigrationContext
    )

{-| This module contains the main program types for a Simplex app.


# Deploying a new app

@docs new


# Migrating an existing app

@docs zeroDowntimeMigration


# Types

@docs BackendProgram, ModelMigrationContext, MsgMigrationContext

-}

import Basics exposing (Bool, Never)
import Elm.Kernel.Simplex
import Platform.Cmd exposing (Cmd)
import Platform.Sub exposing (Sub)
import Result exposing (Result)
import String exposing (String)


{-| Deploy a completely new app.
-}
new :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    }
    -> BackendProgram flags model msg Never
new =
    Elm.Kernel.Simplex.new


{-| Migrate an existing app without any downtime.


## An example migration

We've realized that our amazing incrementing counter app isn't efficient enough. It takes way too many clicks to raise the count by 1000. It would be nice if we could bump the counter by more than 1 at a time.

We'll be migrating it from version 4 to version 5.


### App version 4:

    type Msg
        = Increment

    type alias Model =
        { counter : Int }


### App version 5:

    type Msg = Add Int
    type alias Model = { visits : Int }

    main =
        Simplex.zeroDowntimeMigration
            { update = ...
            , subscriptions = ...
            , migrate =
                { model = \_ oldModel -> Ok { visits = oldModel.counter }
                , msg = \_ oldMsg ->
                    case oldMsg of
                        Increment -> Ok (Add 1)
                }
            }

We'll need to migrate both the model and the messages. That's what the `migrate.model` and `migrate.msg` functions are for.

In order to avoid downtime, we'll run both versions in parallel for a while and then perform a quick switchover. This is the core of the zero-downtime migration algorithm. It's how we are able to process messages during the migration without any data loss. Unfortunately, due to the laws of causality, there is a short time window in which we'll still get the commands and subscriptions from the old app version, but effectively get the model changes from the new app version.

Let's see this well-behaved migration in action, upgrading from version 4 to version 5.

![well-behaved logical time migration example]()

Now let's see a less nicely behaving migration in action, also upgrading from version 4 to version 5.

    ...
    migrate =
        { model = \_ oldModel -> Ok { visits = oldModel.counter + 1337 }
        , msg = \_ oldMsg ->
            case oldMsg of
                Increment -> Ok (Add 13)
        }
    ...

![badly behaved logical time migration example]()

You might think, even though that migration function is crazy, this doesn't look that bad, and I would agree. However, we did tell the world that the counter value was 14, when it was in fact 1363 from the point of view of app version 5. Someone seeing this "wrong" http response could've made some decision based on it that they shouldn't have. Very low likelihood for most apps if you ask me, but if you're interacting with a payment api, it's worth keeping this in mind.


## Possible solutions:

We have a couple of ways to deal with this issue.


### Pessimistic write lock

Add a bool to the model. Whenever the bool is True, you block all reads/writes to the problematic part of the model, e.g. by disabling certain Msg constructors, returning an error response for all such incoming messages.

Flip the bool to True just before the migration. Then migrate the app. Then flip the bool back to False.


### Optimistic write lock

Figure out which message constructs would touch the problematic part of the model. When migrating, if we see a message with one of these bad constructors, and the MsgMigrationContext canMigrationStillBeAborted field is true, return Err to abort the migration. If we manage to perform the full migration without seeing any of the problematic message constructors, we're good. Otherwise we can retry later, for example at night. If the MsgMigrationContext canMigrationStillBeAborted field is false, the migration has finished successfully, and this is a message from an old asynchronous request (e.g. Task, Cmd http request) that arrived just now. You can choose whether to drop it by returning Err, or migrate it by returning Ok.


### Optimistic migration for apps without tasks.

1.  Perform the identity migration, see below.
2.  Migrate the app with a message migration function that always returns an Err if the MsgMigrationContext canMigrationStillBeAborted field is true.
    This way, if we get a single message between when the identity migration starts and when the second migration finishes, the migration will be aborted and the old version will continue serving messages just like before. Any late arriving messages from tagged asynchronous events such as a Task or a Cmd http request will need migrating though, if you care about the response value. Otherwise just return Err. You can tell if the message you've been asked to migrate is one of these late arriving tagged messages by looking at the MsgMigrationContext canMigrationStillBeAborted field; it's False if it's an asynchronous message.


## Checklists

Here's some checklists for safely performing various kinds of changes to your app.

1.  Can you represent all messages from the old app version in the new app version?
2.  Does your new model contain enough information to respond properly to all migrated messages?
3.  Does your new update function respond with similar Cmd's to similar input as the old app version?

Then you're good to go. Otherwise, give it a closer think. Look at the migration diagrams above.


### Identity migrations

It's good practice to run identity migrations on your app just before performing any other migration. It's not at all required, but it'll create a new snapshot which we can start the next migration from, reducing the window of time in which we're running two different app versions in parallel, which in turn reduces the risk of anyone witnessing any inconsistencies, if there are any.

To perform an identity migration, simply use migration functions that don't change anything.

    ...
    migrate =
        { model = \_ oldModel -> Ok oldModel
        , msg = \_ oldMsg -> Ok oldMsg
        }
    ...

You might see a lag spike of up to one second at the exact point the final switchover happens, but it's rarely that big.


### Msg changes

Adding a Msg constructor:

1.  Just add it.

Removing a Msg constructor:

1.  Stop constructing Msgs using the constructor.
2.  Wait until you think that messages constructed with the constructor probably won't show up in the update function anymore, even from Tasks, http requests and other long-running asynchronous sources.
3.  Perform an identity migration. This will lower the probability of the migration seeing any of these old messages.
4.  Perform a migration that returns Err if it does in fact see this Msg.


### Model changes

Expanding the Model:

1.  Just change it.

Removing parts from the Model, e.g. a record field or a constructor:

1.  Just remove it.
2.  Model migration drops that part and all data in it. Msg migration is identity.


### Task/Cmd/Sub/Effect changes

Adding a Sub or an effect triggered when seeing a specific Msg:

1.  Just add it. It'll take effect starting at some specific point in time.

Removing a Sub or an effect triggered when seeing a specific Msg:

1.  Remove it. It'll take effect starting at some specific point in time.
2.  For Subscriptions, no messages will arrive after some point in time during the migration. Messages arriving during the migration but before this point will get migrated using the message migration function.


### More complex changes

Changing part of the Model from a `List User` to a `Dict UserId User`:

1.  Perform a migration:
2.  For messages, previous instructions to insert into the list should now insert into the dict instead.
3.  For the model, convert the List to a Dict, e.g. using List.foldl.


## Err returns from migration functions

If migrate.model or migrate.msg returns Err during the migration, it aborts the migration, and the returned String will show up in the dashboard. This is a great way to know what specifically caused your migration to abort.

If migrate.msg returns Err after the migration has succeeded, on a msg arriving late (e.g. from a long-running Task triggered before the migration succeeded), that one msg will just be silently dropped, so please use this feature carefully.

-}
zeroDowntimeMigration :
    { update : newMsg -> newModel -> ( newModel, Cmd newMsg )
    , subscriptions : newModel -> Sub newMsg
    , migrate :
        { model : ModelMigrationContext -> oldModel -> Result String newModel
        , msg : MsgMigrationContext -> oldMsg -> Result String newMsg
        }
    }
    -> BackendProgram flags newModel newMsg ( oldMsg, oldModel )
zeroDowntimeMigration =
    Elm.Kernel.Simplex.zeroDowntimeMigration


{-| Meta information about the current migration, when migrating the Model.
-}
type alias ModelMigrationContext =
    {}


{-| Meta information about the current migration, when migrating a Msg.
-}
type alias MsgMigrationContext =
    { canMigrationStillBeAborted : Bool
    }


{-| -}
type BackendProgram flags model msg migration
    = BackendProgram
