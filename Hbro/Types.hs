{-# LANGUAGE DeriveDataTypeable #-} 
{-# LANGUAGE ExistentialQuantification #-}
module Hbro.Types where

-- {{{ Imports
import Data.Map
import Data.Set

import Graphics.UI.Gtk.Builder
import Graphics.UI.Gtk.Display.Label
import Graphics.UI.Gtk.Entry.Entry
import Graphics.UI.Gtk.Layout.HBox
import Graphics.UI.Gtk.Gdk.EventM
import Graphics.UI.Gtk.Scrolling.ScrolledWindow
import Graphics.UI.Gtk.WebKit.WebSettings
import Graphics.UI.Gtk.WebKit.WebView
import Graphics.UI.Gtk.Windows.Window

import Network.URI

import System.Console.CmdArgs
import System.Glib.Attributes
import System.Glib.Signals
import System.ZMQ 
-- }}}

    
-- | The whole set of parameters and elements of the browser.
data Environment = Environment {
    mOptions :: CliOptions,               -- ^ Commandline options
    mConfig  :: Config,                   -- ^ Configuration parameters (constants) provided by user
    mGUI     :: GUI,                      -- ^ Graphical widgets
    mContext :: Context                   -- ^ ZMQ context
}

-- | Supported commandline options
data CliOptions = CliOptions {
    mURI             :: Maybe String,     -- ^ URI to load at start-up
    mVanilla         :: Bool,             -- ^ Bypass custom configuration file
    mRecompileOnly   :: Bool,             -- ^ Do not launch browser after recompilation
    mDenyReconf      :: Bool,             -- ^ Do not recompile browser even if configuration file has changed
    mForceReconf     :: Bool,             -- ^ Force recompilation even if configuration file hasn't changed
    mDyreDebug       :: Bool,             -- ^ Look for a custom configuration file in current working directory
    mMasterBinary    :: Maybe String      -- ^ 
} deriving (Data, Typeable, Show, Eq)


data Config = {-forall a.-} Config {
    mCommonDirectories :: CommonDirectories,               -- ^ Custom directories used to store various runtime and static files
    mHomePage          :: String,                          -- ^ Startup page 
    mSocketDir         :: FilePath,                        -- ^ Directory where 0MQ will be created ("/tmp" for example)
    mUIFile            :: FilePath,                        -- ^ Path to XML file describing UI (used by GtkBuilder)
    mKeyEventHandler   :: KeyEventCallback -> ConnectId WebView -> WebView -> EventM EKey Bool,  -- ^ Key event handler, which forwards keystrokes to mKeyEventCallback
    mKeyEventCallback  :: Environment -> KeyEventCallback, -- ^ Main key event callback, assumed to deal with each keystroke separately
    mWebSettings       :: [AttrOp WebSettings],            -- ^ WebSettings' attributes to use with webkit (see Webkit.WebSettings documentation)
    mSetup             :: Environment -> IO (),            -- ^ Custom startup instructions
    mCommands          :: CommandsList,                    -- ^ Custom commands to use with IPC sockets
    mNewWindowHook     :: Environment -> URI -> IO WebView, -- ^ Function triggered on a new window request
    mDownloadHook      :: Environment -> URI -> String -> Int -> IO (), -- ^ Function triggered on a download request
    mError             :: Maybe String                     -- ^ Error
    --mCustom            :: a
}

-- | Various directories used to store some runtime and static files.
data CommonDirectories = CommonDirectories {
    mHome          :: FilePath,        -- ^ Home directory
    mTemporary     :: FilePath,        -- ^ Temporary files directory
    mConfiguration :: FilePath,        -- ^ Configuration directory
    mData          :: FilePath         -- ^ Data directory
}

-- | Graphical elements
data GUI = GUI {
    mWindow             :: Window,          -- ^ Main window
    mInspectorWindow    :: Window,          -- ^ WebInspector window
    mScrollWindow       :: ScrolledWindow,  -- ^ ScrolledWindow containing the webview
    mWebView            :: WebView,         -- ^ Browser's webview
    mPromptBar          :: PromptBar,       -- ^ Prompt bar
    mStatusBar          :: HBox,            -- ^ Status bar's horizontal box
    mBuilder            :: Builder          -- ^ Builder object created from XML file
}

data PromptBar = PromptBar {
    mBox         :: HBox,
    mDescription :: Label, -- ^ Description of current prompt
    mEntry       :: Entry -- ^ Prompt entry
}


-- | List of bound keys.
-- All callbacks are fed with the Environment instance.
-- 
-- Note 1 : for modifiers, lists are used for convenience purposes,
--          but are transformed into sets in hbro's internal machinery,
--          so that order and repetition don't matter.
-- 
-- Note 2 : for printable characters accessed via the shift modifier,
--          you do have to include Shift in modifiers list.
type KeysList         = [(([Modifier], String), IO ())]
type KeysMap          = Map (Set Modifier, String) (IO ())
type KeyEventCallback = [Modifier] -> String -> IO Bool
--data KeyMode          = CommandMode | InsertMode

type CommandsList = [(String, ([String] -> Socket Rep -> Environment -> IO ()))]
type CommandsMap  = Map String ([String] -> Socket Rep -> Environment -> IO ())
