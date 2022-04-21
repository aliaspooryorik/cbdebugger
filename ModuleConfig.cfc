/**
 * Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
 * www.ortussolutions.com
 * ---
 */
component {

	// Module Properties
	this.title              = "ColdBox Debugger";
	this.author             = "Curt Gratz - Ortus Solutions";
	this.version            = "@build.version@+@build.number@";
	this.webURL             = "https://www.ortussolutions.com";
	this.description        = "The ColdBox Debugger Module";
	// If true, looks for views in the parent first, if not found, then in the module. Else vice-versa
	this.viewParentLookup   = true;
	// If true, looks for layouts in the parent first, if not found, then in module. Else vice-versa
	this.layoutParentLookup = true;
	// Module Entry Point
	this.entryPoint         = "cbdebugger";
	// CF Mapping
	this.cfMapping          = "cbdebugger";
	// Model Namespace
	this.modelNamespace     = "cbdebugger";
	// App Helpers
	this.applicationHelper  = [ "helpers/Mixins.cfm" ];

	/**
	 * Module Registration
	 */
	function configure(){
		/**
		 * Settings
		 */
		variables.settings = {
			// This flag enables/disables the tracking of request data to our storage facilities
			// To disable all tracking, turn this master key off
			enabled          : true,
			// This setting controls if you will activate the debugger for visualizations ONLY
			// The debugger will still track requests even in non debug mode.
			debugMode        : controller.getSetting( name = "environment", defaultValue = "production" ) == "development",
			// The URL password to use to activate it on demand
			debugPassword    : "cb:null",
			// This flag enables/disables the end of request debugger panel docked to the bottem of the page.
			// If you disable i, then the only way to visualize the debugger is via the `/cbdebugger` endpoint
			requestPanelDock : true,
			// Request Tracker Options
			requestTracker   : {
				// Store the request profilers in heap memory or in cachebox, default is cachebox
				storage                      : "cachebox",
				// Which cache region to store the profilers in
				cacheName                    : "template",
				// Track all cbdebugger events, by default this is off, turn on, when actually profiling yourself :) How Meta!
				trackDebuggerEvents          : false,
				// Expand by default the tracker panel or not
				expanded                     : false,
				// Slow request threshold in milliseconds, if execution time is above it, we mark those transactions as red
				slowExecutionThreshold       : 1000,
				// How many tracking profilers to keep in stack
				maxProfilers                 : 50,
				// If enabled, the debugger will monitor the creation time of CFC objects via WireBox
				profileWireBoxObjectCreation : false,
				// Profile model objects annotated with the `profile` annotation
				profileObjects               : false,
				// If enabled, will trace the results of any methods that are being profiled
				traceObjectResults           : false,
				// Profile Custom or Core interception points
				profileInterceptions         : false,
				// By default all interception events are excluded, you must include what you want to profile
				includedInterceptions        : [],
				// Control the execution timers
				executionTimers              : {
					expanded           : true,
					// Slow transaction timers in milliseconds, if execution time of the timer is above it, we mark it
					slowTimerThreshold : 250
				},
				// Control the coldbox info reporting
				coldboxInfo : { expanded : false },
				// Control the http request reporting
				httpRequest : {
					expanded        : false,
					// If enabled, we will profile HTTP Body content, disabled by default as it contains lots of data
					profileHTTPBody : false
				}
			},
			// ColdBox Tracer Appender Messages
			tracers     : { enabled : true, expanded : false },
			// Request Collections Reporting
			collections : {
				// Enable tracking
				enabled      : false,
				// Expanded panel or not
				expanded     : false,
				// How many rows to dump for object collections
				maxQueryRows : 50,
				// How many levels to output on dumps for objects
				maxDumpTop   : 5
			},
			// CacheBox Reporting
			cachebox : { enabled : false, expanded : false },
			// Modules Reporting
			modules  : { enabled : false, expanded : false },
			// Quick and QB Reporting
			qb       : {
				enabled   : false,
				expanded  : false,
				// Log the binding parameters
				logParams : true
			},
			// cborm Reporting
			cborm : {
				enabled   : false,
				expanded  : false,
				// Log the binding parameters
				logParams : true
			},
			// Adobe ColdFusion SQL Collector
			acfSql : { enabled : false, expanded : false, logParams : true },
			// Async Manager Reporting
			async  : { enabled : true, expanded : false }
		};

		// Visualizer Route
		router
			.route( "/" )
			.to( "Main.index" )
			.route( "/:action" )
			.toHandler( "Main" );
		;

		/**
		 * Custom Interception Points
		 */
		variables.interceptorSettings = {
			customInterceptionPoints : [
				// Before the debugger panel is rendered
				"beforeDebuggerPanel",
				// After the last debugger panel is rendered
				"afterDebuggerPanel",
				// Before any individual profiler report panels are rendered
				"beforeProfilerReportPanels",
				// After any individual profiler report panels are rendered
				"afterProfilerReportPanels",
				// When the request tracker has been created and placed in request scope
				"onDebuggerRequestTrackerCreation",
				// Before the request tracker is saved in the profiler, last chance to influence the recording
				"onDebuggerProfilerRecording"
			]
		};

		/******************** LOAD AOP MIXER ************************************/

		// Verify if the AOP mixer is loaded, if not, load it
		if ( !isAOPMixerLoaded() ) {
			loadAOPMixer();
		}
	}

	/**
	 * Load the module
	 */
	function onLoad(){
		// Only activate interceptions and collectors if master switch is on or in test mode disable it
		if ( variables.settings.enabled ) {
			/******************** REQUEST COLLECTOR ************************************/

			controller
				.getInterceptorService()
				.registerInterceptor(
					interceptorClass = "#moduleMapping#.interceptors.RequestCollector",
					interceptorName  = "RequestCollector@cbdebugger"
				);

			/******************** PROFILE OBJECTS ************************************/

			if ( variables.settings.requestTracker.profileObjects ) {
				// Object Profiler Aspect
				binder
					.mapAspect( "ObjectProfiler" )
					.to( "#moduleMapping#.aspects.ObjectProfiler" )
					.initArg( name = "traceResults", value = variables.settings.requestTracker.traceObjectResults );

				// Bind Object Aspects to monitor all a-la-carte profilers via method and component annotations
				binder.bindAspect(
					classes = binder.match().any(),
					methods = binder.match().annotatedWith( "profile" ),
					aspects = "ObjectProfiler"
				);
				binder.bindAspect(
					classes = binder.match().annotatedWith( "profile" ),
					methods = binder.match().any(),
					aspects = "ObjectProfiler"
				);
			}

			/******************** PROFILE INTERCEPTIONS ************************************/

			if ( variables.settings.requestTracker.profileInterceptions ) {
				// Register our interceptor profiler
				binder
					.mapAspect( "InterceptorProfiler" )
					.to( "#moduleMapping#.aspects.InterceptorProfiler" )
					.initArg(
						name  = "excludedInterceptions",
						value = controller.getInterceptorService().getInterceptionPoints()
					)
					.initArg(
						name  = "includedInterceptions",
						value = variables.settings.requestTracker.includedInterceptions
					);
				// Intercept all announcements
				binder.bindAspect(
					classes = binder.match().mappings( "coldbox.system.services.InterceptorService" ),
					methods = binder.match().methods( "announce" ),
					aspects = "InterceptorProfiler"
				);
				// Apply AOP
				wirebox.autowire(
					target   = controller.getInterceptorService(),
					targetID = "coldbox.system.services.InterceptorService"
				);
			}

			/******************** QB COLLECTOR ************************************/

			if ( variables.settings.qb.enabled && controller.getModuleService().isModuleRegistered( "qb" ) ) {
				controller
					.getInterceptorService()
					.registerInterceptor(
						interceptorClass = "#moduleMapping#.interceptors.QBCollector",
						interceptorName  = "QBCollector@cbdebugger"
					);
			}

			/******************** QUICK COLLECTOR ************************************/

			if ( variables.settings.qb.enabled && controller.getModuleService().isModuleRegistered( "quick" ) ) {
				controller
					.getInterceptorService()
					.registerInterceptor(
						interceptorClass = "#moduleMapping#.interceptors.QuickCollector",
						interceptorName  = "QuickCollector@cbdebugger"
					);
			}

			/******************** CBORM COLLECTOR ************************************/

			if ( variables.settings.cborm.enabled && controller.getModuleService().isModuleRegistered( "cborm" ) ) {
				controller
					.getInterceptorService()
					.registerInterceptor(
						interceptorClass = "#moduleMapping#.interceptors.CBOrmCollector",
						interceptorName  = "CBOrmCollector@cbdebugger"
					);
			}

			/******************** ACFSQL COLLECTOR ************************************/

			// Do not load on lucee or ACF 2016
			if (
				variables.settings.acfSql.enabled && !server.keyExists( "lucee" ) && server.coldfusion.productVersion.listFirst() gt "2016"
			) {
				controller
					.getInterceptorService()
					.registerInterceptor(
						interceptorClass = "#moduleMapping#.interceptors.ACFSqlCollector",
						interceptorName  = "ACFSqlCollector@cbdebugger"
					);
			} else {
				variables.settings.acfSql.enabled = false;
			}
		}
		// end master switch
	}

	/**
	 * Unloading
	 */
	function onUnload(){
		// Only if we are enabled
		if ( variables.settings.enabled ) {
			controller.getInterceptorService().unregister( "RequestCollector@cbdebugger" );
			controller.getInterceptorService().unregister( "QBCollector@cbdebugger" );
			controller.getInterceptorService().unregister( "QuickCollector@cbdebugger" );
			controller.getInterceptorService().unregister( "CBOrmCollector@cbdebugger" );
			controller.getInterceptorService().unregister( "ACFSqlCollector@cbdebugger" );
		}
	}

	/**
	 * Register our tracer appender after the configuration loads
	 */
	function afterConfigurationLoad(){
		if ( variables.settings.enabled && variables.settings.tracers.enabled ) {
			var logBox = controller.getLogBox();
			logBox.registerAppender( "tracer", "cbdebugger.appenders.TracerAppender" );
			var appenders = logBox.getAppendersMap( "tracer" );
			// Register the appender with the root loggger, and turn the logger on.
			var root      = logBox.getRootLogger();
			root.addAppender( appenders[ "tracer" ] );
			root.setLevelMax( 4 );
			root.setLevelMin( 0 );
		}
	}

	/**
	 * Loads the AOP mixer if not loaded in the application
	 */
	private function loadAOPMixer(){
		// register it
		controller
			.getInterceptorService()
			.registerInterceptor(
				interceptorObject: new coldbox.system.aop.Mixer().configure( wirebox, {} ),
				interceptorName  : "AOPMixer"
			);
	}

	/**
	 * Verify if wirebox aop mixer is loaded
	 */
	private boolean function isAOPMixerLoaded(){
		return wirebox
			.getBinder()
			.getListeners()
			.filter( function( thisListener ){
				return thisListener.class eq "coldbox.system.aop.Mixer";
			} )
			.len() > 0 ? true : false;
	}

}
