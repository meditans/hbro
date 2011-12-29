{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DoRec #-}
module Hbro.Hbro (
-- * Main
    defaultConfig,
    launchHbro
) where

-- {{{ Imports
import Hbro.Core
import Hbro.Gui
import Hbro.Keys
import Hbro.Socket
import Hbro.Types
--import Hbro.Util

import qualified Config.Dyre as D
import Config.Dyre.Paths

import Control.Concurrent
import Control.Monad.Reader

import qualified Data.Map as M

import Graphics.UI.Gtk.Abstract.Widget
import Graphics.UI.Gtk.General.General hiding(initGUI)
import Graphics.UI.Gtk.WebKit.WebView hiding(webViewGetUri)

import System.Console.CmdArgs
import System.Directory
import System.Environment.XDG.BaseDir
import System.FilePath
import System.Glib.Signals
import System.IO
import System.Posix.Process
import System.Posix.Signals
import qualified System.ZMQ as ZMQ
-- }}}

-- {{{ Commandline options
cliOptions :: CliOptions
cliOptions = CliOptions {
    mURI          = def &= help "URI to open at start-up" &= explicit &= name "u" &= name "uri" &= typ "URI",
    mVanilla      = def &= help "Do not read custom configuration file." &= explicit &= name "1" &= name "vanilla",
    mDenyReconf   = def &= help "Deny recompilation even if the configuration file has changed." &= explicit &= name "deny-reconf",
    mForceReconf  = def &= help "Force recompilation even if the configuration file hasn't changed." &= explicit &= name "force-reconf",
    mDyreDebug    = def &= help "Force the application to use './cache/' as the cache directory, and ./ as the configuration directory. Useful to debug the program without installation." &= explicit &= name "dyre-debug",
    mMasterBinary = def &= explicit &= name "dyre-master-binary"
}

getOptions :: IO CliOptions
getOptions = cmdArgs $ cliOptions
    &= verbosityArgs [explicit, name "verbose", name "v"] []
    &= versionArg [ignore]
    &= help "A minimal KISS-compliant browser."
    &= helpArg [explicit, name "help", name "h"]
    &= program "hbro"
-- }}}

-- {{{ Configuration (Dyre)
dyreParameters :: D.Params (Config, CliOptions)
dyreParameters = D.defaultParams {
    D.projectName  = "hbro",
    D.showError    = showError,
    D.realMain     = realMain,
    D.ghcOpts      = ["-threaded"],
    D.statusOut    = hPutStrLn stderr
}

showError :: (Config, a) -> String -> (Config, a)
showError (config, x) message = (config { mError = Just message }, x)

-- | Default configuration.
-- Homepage: Google, socket directory: /tmp,
-- UI file: ~/.config/hbro/, no key/command binding.
defaultConfig :: CommonDirectories -> Config
defaultConfig directories = Config {
    mCommonDirectories = directories,
    mHomePage          = "https://encrypted.google.com/",
    mSocketDir         = mTemporary directories,
    mUIFile            = (mConfiguration directories) ++ pathSeparator:"ui.xml",
    mKeyEventHandler   = simpleKeyEventHandler,
    mKeyEventCallback  = \_ -> simpleKeyEventCallback (keysListToMap []),
    mWebSettings       = [],
    mSetup             = const (return () :: IO ()),
    mCommands          = [],
    mError             = Nothing
}
-- }}}

-- {{{ Entry point
-- | Browser's main function.
-- To be called in main function with a proper configuration.
-- See Hbro.Main for an example.
launchHbro :: (CommonDirectories -> Config) -> IO ()
launchHbro configGenerator = do
    homeDir   <- getHomeDirectory
    tmpDir    <- getTemporaryDirectory
    configDir <- getUserConfigDir "hbro"
    dataDir   <- getUserDataDir   "hbro"
    options   <- getOptions
        
    let config = configGenerator (CommonDirectories homeDir tmpDir configDir dataDir)
    
    case mVanilla options of
        True -> D.wrapMain dyreParameters{ D.configCheck = False } (config, options)
        _    -> D.wrapMain dyreParameters (config, options)

realMain :: (Config, CliOptions) -> IO ()
realMain (config, options) = do
-- Print configuration error, if any
    maybe (return ()) putStrLn $ mError config

-- Print in-use paths
    whenLoud $ getPaths dyreParameters >>= \(a,b,c,d,e) -> do 
        putStrLn ("Current binary:  " ++ a)
        putStrLn ("Custom binary:   " ++ b)
        putStrLn ("Config file:     " ++ c)
        putStrLn ("Cache directory: " ++ d)
        putStrLn ("Lib directory:   " ++ e)
        putStrLn ""
        
-- Initialize GUI
    gui <- initGUI (mUIFile config) (mWebSettings config)

-- Initialize IPC socket
    ZMQ.withContext 1 $ realMain' config options gui

realMain' :: Config -> CliOptions -> GUI -> ZMQ.Context -> IO ()
realMain' config options gui@GUI {mWebView = webView, mWindow = window} context = let
    environment      = Environment options config gui context
    setup            = mSetup config
    socketDir        = mSocketDir config 
    commands         = mCommands config
    keyEventHandler  = mKeyEventHandler config
    keyEventCallback = (mKeyEventCallback config) environment
  in do
-- Apply custom setup
    setup environment
    
-- Setup key handler
    rec i <- after webView keyPressEvent $ keyEventHandler keyEventCallback i webView

-- Load homepage
    case (mURI options) of
        Just uri -> do 
            fileURI <- doesFileExist uri
            case fileURI of
                True -> getCurrentDirectory >>= \dir -> webViewLoadUri webView $ "file://" ++ dir ++ pathSeparator:uri
                _    -> webViewLoadUri webView uri
            
            whenLoud $ putStrLn ("Loading " ++ uri ++ "...")
        _ -> goHome webView config

-- Open socket
    pid              <- getProcessID
    let commandsList = M.fromList $ defaultCommandsList ++ commands
    let socketURI    = "ipc://" ++ socketDir ++ pathSeparator:"hbro." ++ show pid
    void $ forkIO (openRepSocket context socketURI (listenToCommands environment commandsList))
    
-- Manage POSIX signals
    void $ installHandler sigINT (Catch interruptHandler) Nothing

    --timeoutAdd (putStrLn "OK" >> return True) 2000
    mainGUI -- Main loop

-- Make sure response socket is closed at exit
    whenLoud $ putStrLn "Closing socket..."
    closeSocket context socketURI
    whenNormal $ putStrLn "Exiting..."

interruptHandler :: IO ()
interruptHandler = do
    whenLoud $ putStrLn "Received SIGINT."
    mainQuit
-- }}}