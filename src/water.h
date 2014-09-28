/* $Id: water.h 25229 2013-05-06 20:48:18Z planetmaker $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file water.h Functions related to water (management) */

#ifndef WATER_H
#define WATER_H

#include "water_map.h"
#include "economy_func.h"
#include "date_type.h"

/**
 * Describes the behaviour of a tile during flooding.
 */
enum FloodingBehaviour {
	FLOOD_NONE,    ///< The tile does not flood neighboured tiles.
	FLOOD_ACTIVE,  ///< The tile floods neighboured tiles.
	FLOOD_PASSIVE, ///< The tile does not actively flood neighboured tiles, but it prevents them from drying up.
	FLOOD_DRYUP,   ///< The tile drys up if it is not constantly flooded from neighboured tiles.
};

FloodingBehaviour GetFloodingBehaviour(TileIndex tile);

void TileLoop_Water(TileIndex tile);
bool FloodHalftile(TileIndex t);
void DoFloodTile(TileIndex target);

void ConvertGroundTilesIntoWaterTiles();

void DrawShipDepotSprite(int x, int y, Axis axis, DepotPart part);
void DrawWaterClassGround(const struct TileInfo *ti);
void DrawShoreTile(Slope tileh);

void MakeWaterKeepingClass(TileIndex tile, Owner o);

bool RiverModifyDesertZone(TileIndex tile, void *data);

bool IsWateredTile(TileIndex tile, Direction from);

/**
 * Calculates the maintenance cost of a number of canal tiles.
 * @param num Number of canal tiles.
 * @return Total cost.
 */
static inline Money CanalMaintenanceCost(uint32 num)
{
	return (_price[PR_INFRASTRUCTURE_WATER] * HOUR_MULTIPLIER * num * (1 + IntSqrt(num))) >> 6; // 6 bits scaling.
}

#endif /* WATER_H */
