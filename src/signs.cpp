/* $Id: signs.cpp 23319 2011-11-24 17:37:20Z peter1138 $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file signs.cpp Handling of signs. */

#include <iostream>
#include <fstream>
#include "stdafx.h"
#include "landscape.h"
#include "signs_base.h"
#include "signs_func.h"
#include "strings_func.h"
#include "core/pool_func.hpp"

#include "table/strings.h"

/** Initialize the sign-pool */
SignPool _sign_pool("Sign");
INSTANTIATE_POOL_METHODS(Sign)

/**
 * Creates a new sign
 */
Sign::Sign(Owner owner)
{
	this->owner = owner;
}

/** Destroy the sign */
Sign::~Sign()
{
	free(this->name);

	if (CleaningPool()) return;

	DeleteRenameSignWindow(this->index);
}

/**
 * Update the coordinate of one sign
 */
void Sign::UpdateVirtCoord()
{
	Point pt = RemapCoords(this->x, this->y, this->z);
	SetDParam(0, this->index);
	this->sign.UpdatePosition(pt.x, pt.y - 6 * ZOOM_LVL_BASE, STR_WHITE_SIGN);
}

/** Update the coordinates of all signs */
void UpdateAllSignVirtCoords()
{
	Sign *si;

	FOR_ALL_SIGNS(si) {
		si->UpdateVirtCoord();
	}
}

void SaveSignsPreferences()
{
    Sign *si;
    char buffer[255];
    std::ofstream f_obj("signs_prefs.dat");
    FOR_ALL_SIGNS(si) {
        sprintf(buffer, "%d,%d,%s\n", si->x, si->y, si->name);
        f_obj << buffer;
    }
    f_obj.close();
}

