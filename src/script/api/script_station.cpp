/* $Id: script_station.cpp 26398 2014-03-11 22:08:58Z zuu $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file script_station.cpp Implementation of ScriptStation. */

#include "../../stdafx.h"
#include "script_station.hpp"
#include "script_map.hpp"
#include "script_town.hpp"
#include "script_cargo.hpp"
#include "../../station_base.h"
#include "../../roadstop_base.h"
#include "../../town.h"

/* static */ bool ScriptStation::IsValidStation(StationID station_id)
{
	const Station *st = ::Station::GetIfValid(station_id);
	return st != NULL && (st->owner == ScriptObject::GetCompany() || ScriptObject::GetCompany() == OWNER_DEITY || st->owner == OWNER_NONE);
}

/* static */ ScriptCompany::CompanyID ScriptStation::GetOwner(StationID station_id)
{
	if (!IsValidStation(station_id)) return ScriptCompany::COMPANY_INVALID;

	return static_cast<ScriptCompany::CompanyID>((int)::Station::Get(station_id)->owner);
}

/* static */ StationID ScriptStation::GetStationID(TileIndex tile)
{
	if (!::IsValidTile(tile) || !::IsTileType(tile, MP_STATION)) return INVALID_STATION;
	return ::GetStationIndex(tile);
}

/* static */ int32 ScriptStation::GetCargoWaiting(StationID station_id, CargoID cargo_id)
{
	if (!IsValidStation(station_id)) return -1;
	if (!ScriptCargo::IsValidCargo(cargo_id)) return -1;

	return ::Station::Get(station_id)->goods[cargo_id].cargo.TotalCount();
}

/* static */ int32 ScriptStation::GetCargoWaitingFrom(StationID station_id, StationID from_station_id, CargoID cargo_id)
{
	if (!IsValidStation(station_id)) return -1;
	if (!IsValidStation(from_station_id) && from_station_id != STATION_INVALID) return -1;
	if (!ScriptCargo::IsValidCargo(cargo_id)) return -1;

	const StationCargoList &cargo_list = ::Station::Get(station_id)->goods[cargo_id].cargo;
	uint16 cargo_count = 0;
	for (StationCargoList::ConstIterator it = cargo_list.Packets()->begin(); it != cargo_list.Packets()->end(); it++) {
		CargoPacket *cp = *it;
		if (cp->SourceStation() == from_station_id) cargo_count += cp->Count();
	}

	return cargo_count;
}

/* static */ int32 ScriptStation::GetCargoWaitingVia(StationID station_id, StationID via_station_id, CargoID cargo_id)
{
	if (!IsValidStation(station_id)) return -1;
	if (!IsValidStation(via_station_id) && via_station_id != STATION_INVALID) return -1;
	if (!ScriptCargo::IsValidCargo(cargo_id)) return -1;

	const StationCargoList &cargo_list = ::Station::Get(station_id)->goods[cargo_id].cargo;
	uint16 cargo_count = 0;
	std::pair<StationCargoList::ConstIterator, StationCargoList::ConstIterator> range = cargo_list.Packets()->equal_range(via_station_id);
	for (StationCargoList::ConstIterator it = range.first; it != range.second; it++) {
		CargoPacket *cp = *it;
		cargo_count += cp->Count();
	}

	return cargo_count;
}

/* static */ bool ScriptStation::HasCargoRating(StationID station_id, CargoID cargo_id)
{
	if (!IsValidStation(station_id)) return false;
	if (!ScriptCargo::IsValidCargo(cargo_id)) return false;

	return ::Station::Get(station_id)->goods[cargo_id].HasRating();
}

/* static */ int32 ScriptStation::GetCargoRating(StationID station_id, CargoID cargo_id)
{
	if (!ScriptStation::HasCargoRating(station_id, cargo_id)) return -1;

	return ::ToPercent8(::Station::Get(station_id)->goods[cargo_id].rating);
}

/* static */ int32 ScriptStation::GetCoverageRadius(ScriptStation::StationType station_type)
{
	if (station_type == STATION_AIRPORT) return -1;
	if (!HasExactlyOneBit(station_type)) return -1;

	if (!_settings_game.station.modified_catchment) return CA_UNMODIFIED;

	switch (station_type) {
		case STATION_TRAIN:      return CA_TRAIN;
		case STATION_TRUCK_STOP: return CA_TRUCK;
		case STATION_BUS_STOP:   return CA_BUS;
		case STATION_DOCK:       return CA_DOCK;
		default:                 return CA_NONE;
	}
}

/* static */ int32 ScriptStation::GetStationCoverageRadius(StationID station_id)
{
	if (!IsValidStation(station_id)) return -1;

	return Station::Get(station_id)->GetCatchmentRadius();
}

/* static */ int32 ScriptStation::GetDistanceManhattanToTile(StationID station_id, TileIndex tile)
{
	if (!IsValidStation(station_id)) return -1;

	return ScriptMap::DistanceManhattan(tile, GetLocation(station_id));
}

/* static */ int32 ScriptStation::GetDistanceSquareToTile(StationID station_id, TileIndex tile)
{
	if (!IsValidStation(station_id)) return -1;

	return ScriptMap::DistanceSquare(tile, GetLocation(station_id));
}

/* static */ bool ScriptStation::IsWithinTownInfluence(StationID station_id, TownID town_id)
{
	if (!IsValidStation(station_id)) return false;

	return ScriptTown::IsWithinTownInfluence(town_id, GetLocation(station_id));
}

/* static */ bool ScriptStation::HasStationType(StationID station_id, StationType station_type)
{
	if (!IsValidStation(station_id)) return false;
	if (!HasExactlyOneBit(station_type)) return false;

	return (::Station::Get(station_id)->facilities & station_type) != 0;
}

/* static */ bool ScriptStation::HasRoadType(StationID station_id, ScriptRoad::RoadType road_type)
{
	if (!IsValidStation(station_id)) return false;
	if (!ScriptRoad::IsRoadTypeAvailable(road_type)) return false;

	::RoadTypes r = RoadTypeToRoadTypes((::RoadType)road_type);

	for (const RoadStop *rs = ::Station::Get(station_id)->GetPrimaryRoadStop(ROADSTOP_BUS); rs != NULL; rs = rs->next) {
		if ((::GetRoadTypes(rs->xy) & r) != 0) return true;
	}
	for (const RoadStop *rs = ::Station::Get(station_id)->GetPrimaryRoadStop(ROADSTOP_TRUCK); rs != NULL; rs = rs->next) {
		if ((::GetRoadTypes(rs->xy) & r) != 0) return true;
	}

	return false;
}

/* static */ TownID ScriptStation::GetNearestTown(StationID station_id)
{
	if (!IsValidStation(station_id)) return INVALID_TOWN;

	return ::Station::Get(station_id)->town->index;
}

/*static */ bool ScriptStation::IsAirportClosed(StationID station_id)
{
	EnforcePrecondition(false, IsValidStation(station_id));
	EnforcePrecondition(false, HasStationType(station_id, STATION_AIRPORT));

	return (::Station::Get(station_id)->airport.flags & AIRPORT_CLOSED_block) != 0;
}

/*static */ bool ScriptStation::OpenCloseAirport(StationID station_id)
{
	EnforcePrecondition(false, IsValidStation(station_id));
	EnforcePrecondition(false, HasStationType(station_id, STATION_AIRPORT));

	return ScriptObject::DoCommand(0, station_id, 0, CMD_OPEN_CLOSE_AIRPORT);
}
