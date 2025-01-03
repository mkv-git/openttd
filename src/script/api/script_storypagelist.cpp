/* $Id: script_storypagelist.cpp 26304 2014-02-06 19:36:19Z zuu $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file script_storypagelist.cpp Implementation of ScriptStoryPageList and friends. */

#include "../../stdafx.h"
#include "script_storypagelist.hpp"
#include "script_story_page.hpp"
#include "../../story_base.h"

ScriptStoryPageList::ScriptStoryPageList(ScriptCompany::CompanyID company)
{
	uint8 c = company;
	if (company == ScriptCompany::COMPANY_INVALID) c = INVALID_COMPANY;

	StoryPage *p;
	FOR_ALL_STORY_PAGES(p) {
		if (p->company == c || p->company == INVALID_COMPANY) {
			this->AddItem(p->index);
		}
	}
}
