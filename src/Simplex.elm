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

1.  Stop processing incoming msgs
2.  Migrate the model
3.  Start processing incoming msgs again, working through the backlog.

This will naturally mean that the app is unresponsive to requests during the migration, but if the migration is fast enough, the server will e.g. respond to pending http requests after the migration has finished.

If migrate.model or migrate.msg return Nothing during the migration, it aborts the migration. If migrate.msg returns Nothing after the migration has succeeded, on a msg arriving late (e.g. from a long-running Task), that one msg will be dropped.

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
