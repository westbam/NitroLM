////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2006-2007 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

/**
 * Modifications Copyright (c) 2011 Simplified Logic, Inc. http://nitrolm.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *	
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 *  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 *  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 *  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 *  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

package com.nitrolm.modules.mx
{
	
	import flash.utils.ByteArray;
	
	import mx.core.IFlexModuleFactory;
	import mx.modules.IModuleInfo;
	import mx.modules.ModuleManagerGlobals;
	
	/**
	 *  The EncryptedModuleManager class centrally manages dynamically loaded modules.
	 *  It maintains a mapping of URLs to modules.
	 *  A module can exist in a state where it is already loaded
	 *  (and ready for use), or in a not-loaded-yet state.
	 *  The EncryptedModuleManager dispatches events that indicate module status.
	 *  Clients can register event handlers and then call the 
	 *  <code>load()</code> method, which dispatches events when the factory is ready
	 *  (or immediately, if it was already loaded).
	 */
	public class EncryptedModuleManager
	{
		//include "../core/Version.as";
		
		//--------------------------------------------------------------------------
		//
		//  Class methods
		//
		//--------------------------------------------------------------------------
		
		/**
		 *  Get the IModuleInfo interface associated with a particular URL.
		 *  There is no requirement that this URL successfully load,
		 *  but the ModuleManager returns a unique IModuleInfo handle for each unique URL.
		 *  
		 *  @param url A URL that represents the location of the module.
		 *  
		 *  @return The IModuleInfo interface associated with a particular URL.
		 */
		public static function getModule(url:String):IModuleInfo
		{
			return getSingleton().getModule(url);
		}
		
		/**
		 *  See if the referenced object is associated with (or, in the managed
		 *  ApplicationDomain of) a known IFlexModuleFactory implementation.
		 *  
		 *  @param object The object that the ModuleManager tries to create.
		 * 
		 *  @return Returns the IFlexModuleFactory implementation, or <code>null</code>
		 *  if the object type cannot be created from the factory.
		 */
		public static function getAssociatedFactory(
			object:Object):IFlexModuleFactory
		{
			return getSingleton().getAssociatedFactory(object);
		}
		
		/**
		 *  @private
		 *  Typed as Object, for now. Ideally this should be IModuleManager.
		 */
		private static function getSingleton():Object
		{
			if (!ModuleManagerGlobals.managerSingleton || !(ModuleManagerGlobals.managerSingleton is EncryptedModuleManagerImpl))
				ModuleManagerGlobals.managerSingleton = new EncryptedModuleManagerImpl();
			
			return ModuleManagerGlobals.managerSingleton;
		}
	}
	
}

import com.nitrolm.LicenseClient;
import com.nitrolm.NLMConstants;

import flash.display.Loader;
import flash.events.ErrorEvent;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.system.ApplicationDomain;
import flash.system.LoaderContext;
import flash.system.Security;
import flash.system.SecurityDomain;
import flash.utils.ByteArray;
import flash.utils.Dictionary;
import flash.utils.getDefinitionByName;
import flash.utils.getQualifiedClassName;

import mx.core.IFlexModuleFactory;
import mx.events.ModuleEvent;
import mx.modules.IModuleInfo;

/**
 *  @private
 *  ModuleManagerImpl is the Module Manager singleton,
 *  hidden from direct access by the ModuleManager class.
 *  See the documentation for ModuleManager for the details on this class.
 */
class EncryptedModuleManagerImpl extends EventDispatcher
{
	//--------------------------------------------------------------------------
	//
	//  Constructor
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  Constructor.
	 */
	public function EncryptedModuleManagerImpl()
	{
		super();
	}
	
	//--------------------------------------------------------------------------
	//
	//  Variables
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	private var moduleList:Object = {};
	
	//--------------------------------------------------------------------------
	//
	//  Methods
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	public function getAssociatedFactory(object:Object):IFlexModuleFactory
	{
		var className:String = getQualifiedClassName(object);
		
		for each (var m:Object in moduleList)
		{
			var info:EncryptedModuleInfo = m as EncryptedModuleInfo;
			
			if (!info.ready)
				continue;
			
			var domain:ApplicationDomain = info.applicationDomain;
			
			try
			{
				var cls:Class = Class(domain.getDefinition(className));
				if (object is cls)
					return info.factory;
			}
			catch(error:Error)
			{
			}
		}
		
		return null;
	}
	
	/**
	 *  @private
	 */
	public function getModule(url:String):IModuleInfo
	{
		var info:EncryptedModuleInfo = moduleList[url] as EncryptedModuleInfo;
		
		if (!info)
		{
			info = new EncryptedModuleInfo(url);
			moduleList[url] = info;
		}
		
		return new EncryptedModuleInfoProxy(info);
	}
}

////////////////////////////////////////////////////////////////////////////////
//
//  Helper class: ModuleInfo
//
////////////////////////////////////////////////////////////////////////////////

/**
 *  @private
 *  The ModuleInfo class encodes the loading state of a module.
 *  It isn't used directly, because there needs to be only one single
 *  ModuleInfo per URL, even if that URL is loaded multiple times,
 *  yet individual clients need their own dedicated events dispatched
 *  without re-dispatching to clients that already received their events.
 *  ModuleInfoProxy holds the public IModuleInfo implementation
 *  that can be externally manipulated.
 */
class EncryptedModuleInfo extends EventDispatcher
{
	//--------------------------------------------------------------------------
	//
	//  Constructor
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  Constructor.
	 */
	public function EncryptedModuleInfo(url:String)
	{
		super();
		
		_url = url;
	}
	
	//--------------------------------------------------------------------------
	//
	//  Variables
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	private var factoryInfo:FactoryInfo;
	
	/**
	 *  @private
	 */
	private var limbo:Dictionary;
	
	/**
	 *  @private
	 */
	public var loader:Loader;
	
	/**
	 *  @private
	 */
	private var numReferences:int = 0;
	
	
	//--------------------------------------------------------------------------
	//
	//  Properties
	//
	//--------------------------------------------------------------------------
	
	//----------------------------------
	//  applicationDomain
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get applicationDomain():ApplicationDomain
	{
		return !limbo && factoryInfo ? factoryInfo.applicationDomain : null;
	}
	
	//----------------------------------
	//  error
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the error property.
	 */
	private var _error:Boolean = false;
	
	/**
	 *  @private
	 */
	public function get error():Boolean
	{
		return !limbo ? _error : false;
	}
	
	//----------------------------------
	//  factory
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get factory():IFlexModuleFactory
	{
		return !limbo && factoryInfo ? factoryInfo.factory : null;
	}
	
	//----------------------------------
	//  loaded
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the loader property.
	 */
	private var _loaded:Boolean = false;
	
	/**
	 *  @private
	 */
	public function get loaded():Boolean
	{
		return !limbo ? _loaded : false;
	}
	
	//----------------------------------
	//  ready
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the ready property.
	 */
	private var _ready:Boolean = false;
	
	/**
	 *  @private
	 */
	public function get ready():Boolean
	{
		return !limbo ? _ready : false;
	}
	
	//----------------------------------
	//  setup
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the setup property.
	 */
	private var _setup:Boolean = false;
	
	/**
	 *  @private
	 */
	public function get setup():Boolean
	{
		return !limbo ? _setup : false;
	}
	
	//----------------------------------
	//  size
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get size():int
	{
		return !limbo && factoryInfo ? factoryInfo.bytesTotal : 0;
	}
	
	//----------------------------------
	//  url
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the url property.
	 */
	private var _url:String;
	
	/**
	 *  @private
	 */
	public function get url():String
	{
		return _url;
	}
	
	//--------------------------------------------------------------------------
	//
	//  Methods
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	public function load(applicationDomain:ApplicationDomain = null,
						 securityDomain:SecurityDomain = null,
						 bytes:ByteArray = null):void
	{
		if (_loaded)
			return;
		
		var lc:LicenseClient = new LicenseClient(false);
		
		_loaded = true;
		
		limbo = null;
		
		// If bytes are supplied, then load the bytes instead of loading
		// from the url.
		var moduleInfo:EncryptedModuleInfo = this;
		if (bytes)
		{
			var ret:int = lc.decryptAndLoad(moduleInfo, applicationDomain != null ? applicationDomain : new ApplicationDomain(ApplicationDomain.currentDomain), securityDomain, bytes, initHandler, errorHandler, completeHandler);
			if(ret != NLMConstants.RESPONSE_OK)
			{
				errorHandler(new ErrorEvent(ErrorEvent.ERROR, false, false, NLMConstants.responseToString(ret)));
			}
			return;
		}
		
		if (_url.indexOf("published://") == 0)
			return;
		
		var r:URLRequest = new URLRequest(_url);
		
		var urlLoader:URLLoader = new URLLoader();
		urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
		urlLoader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
		urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
		urlLoader.addEventListener(Event.COMPLETE, 
			function urlLoadCompleteHandler(event:Event):void
			{
				var u:URLLoader = event.target as URLLoader; //urlLoader
				var r:ByteArray = u.data as ByteArray; //rawBytes
				
				var ret:int = lc.decryptAndLoad(moduleInfo, applicationDomain != null ? applicationDomain : new ApplicationDomain(ApplicationDomain.currentDomain), securityDomain, r, initHandler, errorHandler, completeHandler);
				if(ret != NLMConstants.RESPONSE_OK)
				{
					errorHandler(new ErrorEvent(ErrorEvent.ERROR, false, false, NLMConstants.responseToString(ret)));
				}
			}
		);
		urlLoader.load(r);
	}
	
	/**
	 *  @private
	 */
	public function resurrect():void
	{
		if (!factoryInfo && limbo)
		{
			//trace("trying to resurrect ", _url, "...");
			for (var f:Object in limbo)
			{
				//trace("found it!");
				factoryInfo = f as FactoryInfo;
				break;
			}
			
			limbo = null;
		}
		
		if (!factoryInfo)
		{
			if (_loaded)
				dispatchEvent(new ModuleEvent(ModuleEvent.UNLOAD));
			
			loader = null;
			_loaded = false;
			_setup = false;
			_ready = false;
			_error = false;
		}
	}
	
	/**
	 *  @private
	 */
	public function release():void
	{
		if (_ready && !limbo)
		{
			// We can try to keep a fully functional factory around
			//trace("putting factory for ", _url, " on ice...");
			limbo = new Dictionary(true);
			limbo[factoryInfo] = 1;
			factoryInfo = null;
		}
		else
		{
			// Otherwise we just drop it
			unload();
		}
	}
	
	/**
	 *  @private
	 */
	
	private function clearLoader():void
	{
		if (loader)
		{
			if (loader.contentLoaderInfo)
			{
				loader.contentLoaderInfo.removeEventListener(
					Event.INIT, initHandler);
				loader.contentLoaderInfo.removeEventListener(
					Event.COMPLETE, completeHandler);
				loader.contentLoaderInfo.removeEventListener(
					ProgressEvent.PROGRESS, progressHandler);
				loader.contentLoaderInfo.removeEventListener(
					IOErrorEvent.IO_ERROR, errorHandler);
				loader.contentLoaderInfo.removeEventListener(
					SecurityErrorEvent.SECURITY_ERROR, errorHandler);
			}
			
			try
			{
				if (loader.content)
				{
					loader.content.removeEventListener("ready", readyHandler);
					loader.content.removeEventListener("error", moduleErrorHandler);
				}
			}
			catch(error:Error)
			{
				// we might get unloaded because of a security error
				// which will disallow access to loader.content
				// so if we get an error here, just ignore it.
			}
			
			
			if (_loaded)
			{
				try
				{
					loader.close();
				}
				catch(error:Error)
				{
				}
			}
			
			try
			{
				loader.unload();
			}
			catch(error:Error)
			{
			}
			
			loader = null;
		}
	}
	/**
	 *  @private
	 */
	public function unload():void
	{
		clearLoader();
		
		if (_loaded)
			dispatchEvent(new ModuleEvent(ModuleEvent.UNLOAD));
		
		limbo = null;
		factoryInfo = null;
		_loaded = false;
		_setup = false;
		_ready = false;
		_error = false;
	}
	
	/**
	 *  @private
	 */
	public function publish(factory:IFlexModuleFactory):void
	{
		if (factoryInfo)
			return; // can't re-publish without unloading.
		
		if (_url.indexOf("published://") != 0)
			return;
		
		factoryInfo = new FactoryInfo();
		factoryInfo.factory = factory;
		_loaded = true;
		_setup = true;
		_ready = true;
		_error = false;
		
		dispatchEvent(new ModuleEvent(ModuleEvent.SETUP));
		dispatchEvent(new ModuleEvent(ModuleEvent.PROGRESS));
		dispatchEvent(new ModuleEvent(ModuleEvent.READY));
	}
	
	/**
	 *  @private
	 */
	public function addReference():void
	{
		++numReferences;
	}
	
	/**
	 *  @private
	 */
	public function removeReference():void
	{
		--numReferences;
		if (numReferences == 0)
			release();
	}
	
	//--------------------------------------------------------------------------
	//
	//  Event handlers
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	public function initHandler(event:Event):void
	{
		//trace("child load of " + _url + " fired init");
		
		factoryInfo = new FactoryInfo();
		
		try
		{
			factoryInfo.factory = loader.content as IFlexModuleFactory;
		}
		catch(error:Error)
		{
		}
		
		if (!factoryInfo.factory)
		{
			var moduleEvent:ModuleEvent = new ModuleEvent(
				ModuleEvent.ERROR, event.bubbles, event.cancelable);
			moduleEvent.bytesLoaded = 0;
			moduleEvent.bytesTotal = 0;
			moduleEvent.errorText = "SWF is not a loadable module";
			dispatchEvent(moduleEvent);
			return;
		}
		
		loader.content.addEventListener("ready", readyHandler);
		loader.content.addEventListener("error", moduleErrorHandler);
		
		try
		{
			factoryInfo.applicationDomain =
				loader.contentLoaderInfo.applicationDomain;
		}
		catch(error:Error)
		{
		}
		_setup = true;
		
		dispatchEvent(new ModuleEvent(ModuleEvent.SETUP));
	}
	
	/**
	 *  @private
	 */
	public function progressHandler(event:ProgressEvent):void
	{
		var moduleEvent:ModuleEvent = new ModuleEvent(
			ModuleEvent.PROGRESS, event.bubbles, event.cancelable);
		moduleEvent.bytesLoaded = event.bytesLoaded;
		moduleEvent.bytesTotal = event.bytesTotal;
		dispatchEvent(moduleEvent);
	}
	
	/**
	 *  @private
	 */
	public function completeHandler(event:Event):void
	{
		//trace("child load of " + _url + " is complete");
		
		var moduleEvent:ModuleEvent = new ModuleEvent(
			ModuleEvent.PROGRESS, event.bubbles, event.cancelable);
		moduleEvent.bytesLoaded = loader.contentLoaderInfo.bytesLoaded;
		moduleEvent.bytesTotal = loader.contentLoaderInfo.bytesTotal;
		dispatchEvent(moduleEvent);
	}
	
	/**
	 *  @private
	 */
	public function errorHandler(event:ErrorEvent):void
	{
		_error = true;
		
		var moduleEvent:ModuleEvent = new ModuleEvent(
			ModuleEvent.ERROR, event.bubbles, event.cancelable);
		moduleEvent.bytesLoaded = 0;
		moduleEvent.bytesTotal = 0;
		moduleEvent.errorText = event.text;
		dispatchEvent(moduleEvent);
		
		//trace("child load of " + _url + " generated an error " + event);
	}
	
	/**
	 *  @private
	 */
	public function readyHandler(event:Event):void
	{
		//trace("child load of " + _url + " is ready");
		
		_ready = true;
		
		factoryInfo.bytesTotal = loader.contentLoaderInfo.bytesTotal;
		
		var moduleEvent:ModuleEvent = new ModuleEvent(ModuleEvent.READY);
		moduleEvent.bytesLoaded = loader.contentLoaderInfo.bytesLoaded;
		moduleEvent.bytesTotal = loader.contentLoaderInfo.bytesTotal;
		
		clearLoader();
		
		dispatchEvent(moduleEvent);
	}
	
	/**
	 *  @private
	 */
	public function moduleErrorHandler(event:Event):void
	{
		//trace("Error: child load of " + _url + ");
		
		_ready = true;
		
		factoryInfo.bytesTotal = loader.contentLoaderInfo.bytesTotal;
		
		clearLoader();
		
		var errorEvent:ModuleEvent;
		
		if (event is ModuleEvent)
			errorEvent = ModuleEvent(event);
		else
			errorEvent = new ModuleEvent(ModuleEvent.ERROR);
		
		dispatchEvent(errorEvent);
	}    
}

////////////////////////////////////////////////////////////////////////////////
//
//  Helper class: FactoryInfo
//
////////////////////////////////////////////////////////////////////////////////

/**
 *  @private
 *  Used for weak dictionary references to a GC-able module.
 */
class FactoryInfo
{
	//--------------------------------------------------------------------------
	//
	//  Constructor
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  Constructor.
	 */
	public function FactoryInfo()
	{
		super();
	}
	
	//--------------------------------------------------------------------------
	//
	//  Properties
	//
	//--------------------------------------------------------------------------
	
	//----------------------------------
	//  factory
	//----------------------------------
	
	/**
	 *  @private
	 */
	public var factory:IFlexModuleFactory;
	
	//----------------------------------
	//  applicationDomain
	//----------------------------------
	
	/**
	 *  @private
	 */
	public var applicationDomain:ApplicationDomain;
	
	//----------------------------------
	//  bytesTotal
	//----------------------------------
	
	/**
	 *  @private
	 */
	public var bytesTotal:int = 0;
}

////////////////////////////////////////////////////////////////////////////////
//
//  Helper class: ModuleInfoProxy
//
////////////////////////////////////////////////////////////////////////////////

/**
 *  @private
 *  ModuleInfoProxy implements IModuleInfo and allows each caller of load()
 *  to have their own dedicated module events, while still using the same
 *  backing load state.
 */
class EncryptedModuleInfoProxy extends EventDispatcher implements IModuleInfo
{
	//--------------------------------------------------------------------------
	//
	//  Constructor
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  Constructor.
	 */
	public function EncryptedModuleInfoProxy(info:EncryptedModuleInfo)
	{
		super();
		
		this.info = info;
		
		info.addEventListener(ModuleEvent.SETUP, moduleEventHandler, false, 0, true);
		info.addEventListener(ModuleEvent.PROGRESS, moduleEventHandler, false, 0, true);
		info.addEventListener(ModuleEvent.READY, moduleEventHandler, false, 0, true);
		info.addEventListener(ModuleEvent.ERROR, moduleEventHandler, false, 0, true);
		info.addEventListener(ModuleEvent.UNLOAD, moduleEventHandler, false, 0, true);
	}
	
	//--------------------------------------------------------------------------
	//
	//  Variables
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	private var info:EncryptedModuleInfo;
	
	/**
	 *  @private
	 */
	private var referenced:Boolean = false;
	
	//--------------------------------------------------------------------------
	//
	//  Properties
	//
	//--------------------------------------------------------------------------
	
	//----------------------------------
	//  data
	//----------------------------------
	
	/**
	 *  @private
	 *  Storage for the data property.
	 */
	private var _data:Object;
	
	/**
	 *  @private
	 */
	public function get data():Object
	{
		return _data;
	}
	
	/**
	 *  @private
	 */
	public function set data(value:Object):void
	{
		_data = value;
	}
	
	//----------------------------------
	//  error
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get error():Boolean
	{
		return info.error;
	}
	
	//----------------------------------
	//  factory
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get factory():IFlexModuleFactory
	{
		return info.factory;
	}
	
	//----------------------------------
	//  loaded
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get loaded():Boolean
	{
		return info.loaded;
	}
	
	//----------------------------------
	//  ready
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get ready():Boolean
	{
		return info.ready;
	}
	
	//----------------------------------
	//  setup
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get setup():Boolean
	{
		return info.setup;
	}
	
	//----------------------------------
	//  url
	//----------------------------------
	
	/**
	 *  @private
	 */
	public function get url():String
	{
		return info.url;
	}
	
	//--------------------------------------------------------------------------
	//
	//  Methods
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	public function publish(factory:IFlexModuleFactory):void
	{
		info.publish(factory);
	}
	
	/**
	 *  @private
	 */
	public function load(applicationDomain:ApplicationDomain = null,
						 securityDomain:SecurityDomain = null,
						 bytes:ByteArray = null):void
	{
		info.resurrect();
		
		if (!referenced)
		{
			info.addReference();
			referenced = true;
		}
		
		//trace("Module[", url, "] load");
		
		if (info.error)
		{
			//trace("Module[", url, "] load is in error state");
			dispatchEvent(new ModuleEvent(ModuleEvent.ERROR));
		}
		else if (info.loaded)
		{
			//trace("Module[", url, "] load is already loaded");
			
			if (info.setup)
			{
				//trace("Module[", url, "] load is already set up");
				dispatchEvent(new ModuleEvent(ModuleEvent.SETUP));
				
				if (info.ready)
				{
					//trace("Module[", url, "] load is already ready");
					
					var moduleEvent:ModuleEvent =
						new ModuleEvent(ModuleEvent.PROGRESS);
					moduleEvent.bytesLoaded = info.size;
					moduleEvent.bytesTotal = info.size;
					dispatchEvent(moduleEvent);
					
					dispatchEvent(new ModuleEvent(ModuleEvent.READY));
				}
			}
		}
		else
		{
			info.load(applicationDomain, securityDomain, bytes);
		}
	}
	
	/**
	 *  @private
	 */
	public function release():void
	{
		if (referenced)
		{
			info.removeReference();
			referenced = false;
		}
	}
	
	/**
	 *  @private
	 */
	public function unload():void
	{
		info.unload();
		
		info.removeEventListener(ModuleEvent.SETUP, moduleEventHandler);
		info.removeEventListener(ModuleEvent.PROGRESS, moduleEventHandler);
		info.removeEventListener(ModuleEvent.READY, moduleEventHandler);
		info.removeEventListener(ModuleEvent.ERROR, moduleEventHandler);
		info.removeEventListener(ModuleEvent.UNLOAD, moduleEventHandler);
	}
	
	//--------------------------------------------------------------------------
	//
	//  Event handlers
	//
	//--------------------------------------------------------------------------
	
	/**
	 *  @private
	 */
	private function moduleEventHandler(event:ModuleEvent):void
	{
		dispatchEvent(event);
	}
}
