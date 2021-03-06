module Text.PDF.Slave.Server.Client(
    PDFSlaveClientConfig(..)
  , PDFSlaveClientM
  , runPDFSlaveClientM
  , renderTemplate
  , APIRenderId
  , fromAPIRenderId
  , toAPIRenderId
  ) where

import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Reader
import Data.Aeson (Value)
import Data.Proxy
import Data.Text (Text, unpack)
import Network.HTTP.Client (Manager)
import Network.HTTP.Client.TLS
import Servant.Client
import Text.PDF.Slave.Server.API

-- | Client configuration
data PDFSlaveClientConfig = PDFSlaveClientConfig {
  -- | Connection URL
  pdfSlaveUrl :: Text
  -- | Where to post notification
, pdfSlaveReturnUrl :: Text
  -- | Optional connection manager
, pdfSlaveManager :: Maybe Manager
}

-- | Environment of 'PDFSlaveClientM' monad
data PDFSlaveClientEnv = PDFSlaveClientEnv {
  envReturnUrl :: Text
}

-- | Wrapper for client monad
newtype PDFSlaveClientM a = PDFSlaveClientM { unPDFSlaveClientM :: ReaderT PDFSlaveClientEnv ClientM a }
  deriving (Functor, Applicative, Monad, MonadIO, MonadThrow, MonadCatch
    , MonadReader PDFSlaveClientEnv)

-- | Execute client actions
runPDFSlaveClientM :: (MonadIO m, MonadThrow m)
  => PDFSlaveClientConfig -- ^ Configuration of client
  -> PDFSlaveClientM a -- ^ Client action
  -> m (Either ServantError a)
runPDFSlaveClientM PDFSlaveClientConfig{..} m = do
  baseUrl <- parseBaseUrl (unpack pdfSlaveUrl)
  mng <- case pdfSlaveManager of
    Nothing -> liftIO getGlobalManager
    Just mng -> return mng
  let env = PDFSlaveClientEnv {
          envReturnUrl = pdfSlaveReturnUrl
        }
  liftIO $ runClientM (runReaderT (unPDFSlaveClientM m) env) (ClientEnv mng baseUrl)

-- | Lifting 'ClientM' actions into 'PDFSlaveClientM' monad
liftClientM :: ClientM a -> PDFSlaveClientM a
liftClientM = PDFSlaveClientM . lift

-- | Send template bundle with input for rendering
renderTemplate :: Template -- ^ Template bundle to render
  -> Maybe APIRenderId -- ^ Optional id overwrite
  -> Maybe Value -- ^ Optional value
  -> PDFSlaveClientM APIRenderId
renderTemplate t mid minput = do
  url <- asks envReturnUrl
  OnlyField i <- liftClientM $ renderTemplateEndpoint APIRenderBody {
      apiRenderBodyId = mid
    , apiRenderBodyTemplate = t
    , apiRenderBodyInput = minput
    , apiRenderBodyUrl = url
    }
  return i

renderTemplateEndpoint :: APIRenderBody -> ClientM (OnlyId APIRenderId)
( renderTemplateEndpoint
  ) = client (Proxy :: Proxy PDFSlaveAPI)