{-|
Module      : Network.Pusher.Internal
Description : Pure functions called by the public interface
Copyright   : (c) Will Sewell, 2016
Licence     : MIT
Maintainer  : me@willsewell.com
Stability   : experimental
-}
module Network.Pusher.Internal
  ( mkTriggerRequest
  , mkChannelsRequest
  , mkChannelRequest
  , mkUsersRequest
  ) where

import Control.Monad (when)
import qualified Data.Aeson as A
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (maybeToList)
import Data.Monoid ((<>))
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word64)

import Network.Pusher.Data
       (Channel, ChannelType, Credentials(..), Event, EventData,
        Pusher(..), SocketID, renderChannel, renderChannelPrefix)
import Network.Pusher.Error (PusherError(..))
import Network.Pusher.Internal.Auth (makeQS)
import Network.Pusher.Internal.HTTP
       (RequestBody, RequestParams(RequestParams), RequestQueryString)
import Network.Pusher.Protocol
       (ChannelInfoQuery, ChannelsInfoQuery, toURLParam)

mkTriggerRequest ::
     Pusher
  -> [Channel]
  -> Event
  -> EventData
  -> Maybe SocketID
  -> Word64
  -> Either PusherError (RequestParams, RequestBody)
mkTriggerRequest pusher chans event dat socketId timestamp = do
  when
    (length chans > 10)
    (Left $ PusherArgumentError "Must be less than 10 channels")
  let body =
        A.object $
        [ ("name", A.String event)
        , ("channels", A.toJSON (map (A.String . renderChannel) chans))
        , ("data", A.String dat)
        ] ++
        maybeToList (fmap (\sID -> ("socket_id", A.String sID)) socketId)
      bodyBS = BL.toStrict $ A.encode body
  when
    (B.length bodyBS > 10000)
    (Left $ PusherArgumentError "Body must be less than 10000 bytes long")
  return (mkPostRequest pusher "events" [] bodyBS timestamp, body)

mkChannelsRequest ::
     Pusher
  -> Maybe ChannelType
  -> T.Text
  -> ChannelsInfoQuery
  -> Word64
  -> RequestParams
mkChannelsRequest pusher channelTypeFilter prefixFilter attributes timestamp =
  let prefix = maybe "" renderChannelPrefix channelTypeFilter <> prefixFilter
      params =
        [ ("info", encodeUtf8 $ toURLParam attributes)
        , ("filter_by_prefix", encodeUtf8 prefix)
        ]
  in mkGetRequest pusher "channels" params timestamp

mkChannelRequest ::
     Pusher -> Channel -> ChannelInfoQuery -> Word64 -> RequestParams
mkChannelRequest pusher chan attributes timestamp =
  let params = [("info", encodeUtf8 $ toURLParam attributes)]
      subPath = "channels/" <> renderChannel chan
  in mkGetRequest pusher subPath params timestamp

mkUsersRequest :: Pusher -> Channel -> Word64 -> RequestParams
mkUsersRequest pusher chan timestamp =
  let subPath = "channels/" <> renderChannel chan <> "/users"
  in mkGetRequest pusher subPath [] timestamp

mkGetRequest ::
     Pusher
  -> T.Text
  -> RequestQueryString
  -> Word64
  -> RequestParams
mkGetRequest pusher subPath params timestamp =
  let (ep, fullPath) = mkEndpoint pusher subPath
      qs = mkQS pusher "GET" fullPath params "" timestamp
  in RequestParams ep qs

mkPostRequest ::
     Pusher
  -> T.Text
  -> RequestQueryString
  -> B.ByteString
  -> Word64
  -> RequestParams
mkPostRequest pusher subPath params bodyBS timestamp =
  let (ep, fullPath) = mkEndpoint pusher subPath
      qs = mkQS pusher "POST" fullPath params bodyBS timestamp
  in RequestParams ep qs

-- |Build a full endpoint from the details in Pusher and the subPath.
mkEndpoint ::
     Pusher
  -> T.Text -- ^The subpath of the specific request, e.g "events/channel-name".
  -> (T.Text, T.Text) -- ^The full endpoint, and just the path component.
mkEndpoint pusher subPath =
  let fullPath = pusherPath pusher <> subPath
      endpoint = pusherHost pusher <> fullPath
  in (endpoint, fullPath)

mkQS
  :: Pusher
  -> T.Text
  -> T.Text
  -> RequestQueryString
  -> B.ByteString
  -> Word64
  -> RequestQueryString
mkQS pusher =
  let credentials = pusherCredentials pusher
  in makeQS (credentialsAppKey credentials) (credentialsAppSecret credentials)
