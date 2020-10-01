module Simplex exposing
    ( new
    , zeroDowntimeMigration
    , BackendProgram(..)
    )

{-| This module contains the main program types for a Simplex app.


# Deploying a new app

@docs new


# Migrating an existing app

@docs zeroDowntimeMigration


# Types

@docs BackendProgram

-}

import Basics exposing (Never)
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

These two paths must result in equivalent models, given the exact same msg:
1. Run old update function: (updateFn msg model)
2. Migrate model
And secondly:
1. Migrate model
2. Run new update function: (updateFn (migrate msg) migratedModel)

This is the core of the zero-downtime migration algorithm. It's how we are able to process messages during the migration without any data loss. It probably sounds much stricter than it actually is, so here's a bunch of examples:


## Msg changes

Adding a Msg constructor:
1. Just add it.

Removing a Msg constructor:
1. Stop constructing Msgs using the constructor.
2. Wait until you think that messages constructed with the constructor probably won't show up in the update function anymore, even from Tasks, http requests and other long-running asynchronous sources.
3. Perform an identity migration. This will lower the probability of the migration seeing any of these old messages.
4. Perform a migration that fails (returns Err) if it does in fact see this Msg.


## Model changes

Adding fields to the Model:
1. Just add it.

Removing parts from the Model, e.g. a record field:
1. Just remove it.
2. Model migration drops that part and all data in it. Msg migration is identity.


## Task/Cmd/Sub/Effect changes

Adding a Sub or an effect triggered when seeing a specific Msg:
1. Just add it. It'll take effect starting at some specific point in time.

Removing a Sub or an effect triggered when seeing a specific Msg:
1. Remove it. It'll take effect starting at some specific point in time.
2. For Subscriptions, no messages will arrive after some point in time during the migration. Messages arriving during the migration but before this point will get migrated using the message migration function.

## More complex changes

Changing part of the Model from a List User to Dict UserId User:
1. Perform a migration:
2. For messages, previous instructions to insert into the list should now insert into the dict instead.
3. For the model, convert the List to a Dict, e.g. using List.foldl.


## What if I can't follow those rules?

Please do tell us about it! We haven't found a single migration yet that couldn't be performed by breaking it into smaller pieces first.

If you're ok with some of the resulting messages from tasks and cmds performed during a migration being dropped, you can do this:
1. Perform an identity migration, to create a fresh backup.
2. Migrate again, using `always (Err "refusing to process a single msg in two appVersions at once")` as the msg migration function.
3. If a single msg arrived between when the backup was made and when the second migration finished, the old app will handle it and the migration will be rolled back. No problem, just start over at step 1 again, maybe even at night or whenever traffic is the lowest.
4. If no msg arrives between when the backup was made and when the second migration finished, we're done, the migration will be applied.


## What if I don't follow those rules?

No big deal.

Externally, it'll seem like you're talking to the old app first, and then to the new app. The new app will get its state constructed by loading from a backup, then migrating and processing all messages from when the backup was made until now. Then it'll take over processing messages from the old app version.

If you have user flows that rely on multiple passes through he update fn and you forget where they were in the flow, they'll probably have to start over again. If you leave the model in an inconsistent state where e.g. an account has both been created and not been created, it might be a bit tricky to fix it up.

If you perform an identity migration first, it'll create a fresh backup file while doing so, minimizing the number of old messages processed by both app versions, which will reduce the opportunities for the two versions to diverge. Running the migration at a low-traffic time of day will also help.

# Err returns from migration functions

If migrate.model or migrate.msg returns Err during the migration, it aborts the migration, and the returned String will show up in the dashboard. This is a great way to know what specifically caused your migration to abort.

If migrate.msg returns Err after the migration has succeeded, on a msg arriving late (e.g. from a long-running Task triggered before the migration succeeded), that one msg will just be silently dropped, so please use this feature carefully.

-}
zeroDowntimeMigration :
    { update : newMsg -> newModel -> ( newModel, Cmd newMsg )
    , subscriptions : newModel -> Sub newMsg
    , migrate :
        { model : oldModel -> Result String newModel
        , msg : oldMsg -> Result String newMsg
        }
    }
    -> BackendProgram flags newModel newMsg ( oldMsg, oldModel )
zeroDowntimeMigration =
    Elm.Kernel.Simplex.zeroDowntimeMigration


{-| -}
type BackendProgram flags model msg migration
    = BackendProgram
