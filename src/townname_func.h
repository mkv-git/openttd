/* $Id: townname_func.h 26313 2014-02-06 21:06:59Z rubidium $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file townname_func.h %Town name generator stuff. */

#ifndef TOWNNAME_FUNC_H
#define TOWNNAME_FUNC_H

#include "townname_type.h"

char *GenerateTownNameString(char *buf, const char *last, size_t lang, uint32 seed);
char *GetTownName(char *buff, const TownNameParams *par, uint32 townnameparts, const char *last);
char *GetTownName(char *buff, const Town *t, const char *last);
bool VerifyTownName(uint32 r, const TownNameParams *par, TownNames *town_names = NULL);
bool GenerateTownName(uint32 *townnameparts, TownNames *town_names = NULL);
const char *FetchTownName(const Town *town);

#endif /* TOWNNAME_FUNC_H */
