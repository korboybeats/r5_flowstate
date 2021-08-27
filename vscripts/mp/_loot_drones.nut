//=========================================================
//	_loot_drones.nut
//=========================================================

global function InitLootDrones
global function InitLootDronePaths

global function SpawnLootDrones


//////////////////////
//////////////////////
//// Global Types ////
//////////////////////
//////////////////////
global const string LOOT_DRONE_PATH_NODE_ENTNAME = "loot_drone_path_node"

global const float LOOT_DRONE_START_NODE_SELECTION_MIN_DISTANCE = 50


///////////////////////
///////////////////////
//// Private Types ////
///////////////////////
///////////////////////
struct {
	array<array<entity> > dronePaths

	table<entity, LootDroneData> droneData
} file


/////////////////////////
/////////////////////////
//// Initialiszation ////
/////////////////////////
/////////////////////////
void function InitLootDrones()
{
	RegisterSignal( SIGNAL_LOOT_DRONE_FALL_START )
	RegisterSignal( SIGNAL_LOOT_DRONE_STOP_PANIC )

	FlagInit( "DronePathsInitialized", false )
}

void function InitLootDronePaths()
{
	// Get all drone path nodes (mixed)
	array<entity> dronePathNodes = GetEntArrayByScriptName( LOOT_DRONE_PATH_NODE_ENTNAME )

	// No nodes on this map?
	if ( dronePathNodes.len() == 0 )
	{
		Warning( "%s() - No path nodes of script name %s found! Paths were not initialized.", FUNC_NAME(), LOOT_DRONE_PATH_NODE_ENTNAME )
		return
	}

	// Separate nodes into groups
	while ( dronePathNodes.len() > 0 )
	{
		// Get a random node
		entity node = dronePathNodes.getrandom()

		// Get all nodes associated with it
		array<entity> groupNodes = GetEntityLinkLoop( node )

		// Remove this group's nodes from the list
		foreach ( entity groupNode in groupNodes )
			dronePathNodes.fastremovebyvalue( groupNode )

		// Add the group to the path list
		file.dronePaths.append( groupNodes )
	}

	printf( "DronePaths: found %i paths", file.dronePaths.len() )

	// Mark drone paths as initialized
	FlagSet( "DronePathsInitialized" )
}


//////////////////////////
//////////////////////////
//// Global functions ////
//////////////////////////
//////////////////////////
array<LootDroneData> function SpawnLootDrones( int numToSpawn )
{
	array<LootDroneData> drones

	for ( int i = 0; i < numToSpawn; ++i )
		drones.append( LootDrones_SpawnLootDroneAtRandomPath() )

	return drones
}

//////////////////////////
//////////////////////////
/// Internal functions ///
//////////////////////////
//////////////////////////
array<entity> function LootDrones_GetRandomPath()
{
	Assert( !Flag( "DronePathsInitialized" ), "Trying to get a random path while having uninitialized paths!" )

	return file.dronePaths.getrandom()
}

LootDroneData function LootDrones_SpawnLootDroneAtRandomPath()
{
	LootDroneData data

	array<entity> path = LootDrones_GetRandomPath()
	if ( path.len() == 0 )
	{
		Assert( 0, "Got a random path with no nodes!" )
		return data
	}

	// Get available start node
	entity ornull startNode = LootDrones_GetAvailableStartNodeFromPath( path )

	if ( startNode == null )
	{
		Assert( 0, "Got a random path with no available start node!" )
		return data
	}

	expect entity( startNode )

	// Set path from this start node.
	data.path = GetEntityLinkLoop( startNode )
	foreach ( entity pathNode in data.path )
		data.pathVec.append( pathNode.GetOrigin() )

	// Create the visible drone model using the model const.
	// is this the correct way of doing this?
	entity model = CreatePropScript( LOOT_DRONE_MODEL, startNode.GetOrigin(), startNode.GetAngles() )
	
	model.DisableHibernation()

	model.SetMaxHealth( LOOT_DRONE_HEALTH_MAX )
	model.SetHealth( LOOT_DRONE_HEALTH_MAX )

	// Set model entity in the struct.
	data.model = model

	// Create script mover for moving. (not for now?)
	data.mover = CreateOwnedScriptMover( model )

	// Use the same mover for rotating.
	data.rotator = data.mover

	// Use model entity for sounds.
	data.soundEntity = model

	// Create and attach loot roller.
	// TODO

	file.droneData[ model ] <- data

	thread LootDroneState( data )
	thread LootDroneMove( data )

	return data
}

entity ornull function LootDrones_GetAvailableStartNodeFromPath( array<entity> path )
{
	foreach ( entity pathNode in path )
	{
		vector nodeOrigin = pathNode.GetOrigin()

		bool suitable = true

		foreach ( entity model, LootDroneData data in file.droneData )
		{
			// Too close?
			if ( Distance( nodeOrigin, model.GetOrigin() ) <= LOOT_DRONE_START_NODE_SELECTION_MIN_DISTANCE )
			{
				// Bail.
				suitable = false
				break
			}
		}

		if ( suitable )
			return pathNode
	}

	return null
}

void function LootDroneState( LootDroneData data )
{
	Assert( IsNewThread(), "Must be threaded off" )

	data.model.EndSignal( "OnDestroy" )
	data.model.EndSignal( "OnDeath" )

	OnThreadEnd(
		function() : ( data )
		{
			if ( IsValid( data.soundEntity ) )
				StopSoundOnEntity( data.soundEntity, LOOT_DRONE_LIVING_SOUND )
		}
	)

	EmitSoundOnEntity( data.soundEntity, LOOT_DRONE_LIVING_SOUND )
}

void function LootDroneMove( LootDroneData data )
{
	Assert( IsNewThread(), "Must be threaded off" )

	data.model.EndSignal( "OnDestroy" )
	data.model.EndSignal( SIGNAL_LOOT_DRONE_FALL_START )

	OnThreadEnd(
		function() : ( data )
		{
			if ( IsValid( data.mover ) )
				data.mover.Train_StopImmediately()
		}
	)

	// Remove the current node from the lists
	data.path.fastremove( 0 )
	data.pathVec.fastremove( 0 )

	while ( true )
	{
		entity nextNode = data.path[0]

		printf( "%s() - next node: %s", FUNC_NAME(), string( nextNode ) )

		data.mover.Train_MoveToTrainNode( nextNode, data.__maxSpeed, data.__accel )

		printf( 
			"%s() -  move command sent, time to goal speed: %f, goal speed: %f, last distance: %f, current speed: %f", 
			
			FUNC_NAME(), 

			data.mover.Train_GetTotalTimeToGoalSpeed(),
			data.mover.Train_GetGoalSpeed(),
			data.mover.Train_GetLastDistance(),
			data.mover.Train_GetCurrentSpeed()
		)

		printt( data.mover.GetOrigin() )
		
		wait data.mover.Train_GetTotalTimeToGoalSpeed()
		WaitForever()
		// wait ( Distance( nextNode.GetOrigin(), data.mover.GetOrigin() ) / data.mover.Train_GetCurrentSpeed() ) // Very rough approximation.

		/*data.path.fastremove( 0 )
		data.pathVec.fastremove( 0 )

		entity currentNode = data.mover.Train_GetLastNode()

		if ( data.pathVec.len() == 0 )
		{
			// Set path from current node.
			data.path = GetEntityLinkLoop( currentNode )
			foreach ( entity pathNode in data.path )
				data.pathVec.append( pathNode.GetOrigin() )
		}*/
	}
}

// void function LootDroneSound( LootDroneData data )
// {
// 	Assert( IsNewThread(), "Must be threaded off" )

// 	EmitSoundOnEntity( data.model, LOOT_DRONE_LIVING_SOUND )

// 	data.model.WaitSignal( "OnDeath" )

// 	StopSoundOnEntity( data.model, LOOT_DRONE_LIVING_SOUND )
// 	EmitSoundOnEntity( data.model, LOOT_DRONE_DEATH_SOUND )

// 	data.model.WaitSignal( SIGNAL_LOOT_DRONE_FALL_START )

// 	EmitSoundOnEntity( data.model, LOOT_DRONE_CRASHING_SOUND )

// 	data.model.WaitSignal( "OnDestroy" )
	
// 	StopSoundOnEntity( data.model, LOOT_DRONE_CRASHING_SOUND )
// 	EmitSoundOnEntity( data.model, LOOT_DRONE_CRASHED_SOUND )
// }