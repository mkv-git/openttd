/* $Id: refresh.cpp 26283 2014-01-28 19:49:43Z fonsinchen $ */

/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <http://www.gnu.org/licenses/>.
 */

/** @file refresh.h Definition of link refreshing utility. */

#include "../stdafx.h"
#include "../core/bitmath_func.hpp"
#include "../station_func.h"
#include "../engine_base.h"
#include "../vehicle_func.h"
#include "refresh.h"
#include "linkgraph.h"

/**
 * Refresh all links the given vehicle will visit.
 * @param v Vehicle to refresh links for.
 * @param allow_merge If the refresher is allowed to merge or extend link graphs.
 */
/* static */ void LinkRefresher::Run(Vehicle *v, bool allow_merge)
{
	/* If there are no orders we can't predict anything.*/
	if (v->orders.list == NULL) return;

	/* Make sure the first order is a useful order. */
	const Order *first = v->orders.list->GetNextDecisionNode(v->GetOrder(v->cur_implicit_order_index), 0);
	if (first == NULL) return;

	HopSet seen_hops;
	LinkRefresher refresher(v, &seen_hops, allow_merge);

	refresher.RefreshLinks(first, first, v->last_loading_station != INVALID_STATION ? 1 << HAS_CARGO : 0);
}

/**
 * Comparison operator to allow hops to be used in a std::set.
 * @param other Other hop to be compared with.
 * @return If this hop is "smaller" than the other (defined by from, to and cargo in this order).
 */
bool LinkRefresher::Hop::operator<(const Hop &other) const
{
	if (this->from < other.from) {
		return true;
	} else if (this->from > other.from) {
		return false;
	}
	if (this->to < other.to) {
		return true;
	} else if (this->to > other.to) {
		return false;
	}
	return this->cargo < other.cargo;
}

/**
 * Constructor for link refreshing algorithm.
 * @param vehicle Vehicle to refresh links for.
 * @param seen_hops Set of hops already seen. This is shared between this
 *                  refresher and all its children.
 * @param allow_merge If the refresher is allowed to merge or extend link graphs.
 */
LinkRefresher::LinkRefresher(Vehicle *vehicle, HopSet *seen_hops, bool allow_merge) :
		vehicle(vehicle), seen_hops(seen_hops), cargo(CT_INVALID), allow_merge(allow_merge)
{
	/* Assemble list of capacities and set last loading stations to 0. */
	for (Vehicle *v = this->vehicle; v != NULL; v = v->Next()) {
		this->refit_capacities.push_back(RefitDesc(v->cargo_type, v->cargo_cap, v->refit_cap));
		if (v->refit_cap > 0) this->capacities[v->cargo_type] += v->refit_cap;
	}
}

/**
 * Handle refit orders by updating capacities and refit_capacities.
 * @param next Order to be processed.
 */
void LinkRefresher::HandleRefit(const Order *next)
{
	this->cargo = next->GetRefitCargo();
	RefitList::iterator refit_it = this->refit_capacities.begin();
	for (Vehicle *v = this->vehicle; v != NULL; v = v->Next()) {
		const Engine *e = Engine::Get(v->engine_type);
		if (!HasBit(e->info.refit_mask, this->cargo)) {
			++refit_it;
			continue;
		}

		/* Back up the vehicle's cargo type */
		CargoID temp_cid = v->cargo_type;
		byte temp_subtype = v->cargo_subtype;
		v->cargo_type = this->cargo;
		v->cargo_subtype = GetBestFittingSubType(v, v, this->cargo);

		uint16 mail_capacity = 0;
		uint amount = e->DetermineCapacity(v, &mail_capacity);

		/* Restore the original cargo type */
		v->cargo_type = temp_cid;
		v->cargo_subtype = temp_subtype;

		/* Skip on next refit. */
		if (this->cargo != refit_it->cargo && refit_it->remaining > 0) {
			this->capacities[refit_it->cargo] -= refit_it->remaining;
			refit_it->remaining = 0;
		} else if (amount < refit_it->remaining) {
			this->capacities[refit_it->cargo] -= refit_it->remaining - amount;
			refit_it->remaining = amount;
		}
		refit_it->capacity = amount;
		refit_it->cargo = this->cargo;

		++refit_it;

		/* Special case for aircraft with mail. */
		if (v->type == VEH_AIRCRAFT) {
			if (mail_capacity < refit_it->remaining) {
				this->capacities[refit_it->cargo] -= refit_it->remaining - mail_capacity;
				refit_it->remaining = mail_capacity;
			}
			refit_it->capacity = mail_capacity;
			break; // aircraft have only one vehicle
		}
	}
}

/**
 * Restore capacities and refit_capacities as vehicle might have been able to load now.
 */
void LinkRefresher::ResetRefit()
{
	for (RefitList::iterator it(this->refit_capacities.begin()); it != this->refit_capacities.end(); ++it) {
		if (it->remaining == it->capacity) continue;
		this->capacities[it->cargo] += it->capacity - it->remaining;
		it->remaining = it->capacity;
	}
}

/**
 * Predict the next order the vehicle will execute and resolve conditionals by
 * recursion and return next non-conditional order in list.
 * @param cur Current order being evaluated.
 * @param next Next order to be evaluated.
 * @param flags RefreshFlags to give hints about the previous link and state carried over from that.
 * @param num_hops Number of hops already taken by recursive calls to this method.
 * @return new next Order.
 */
const Order *LinkRefresher::PredictNextOrder(const Order *cur, const Order *next, uint8 flags, uint num_hops)
{
	/* next is good if it's either NULL (then the caller will stop the
	 * evaluation) or if it's not conditional and the caller allows it to be
	 * chosen (by setting USE_NEXT). */
	while (next != NULL && (!HasBit(flags, USE_NEXT) || next->IsType(OT_CONDITIONAL))) {

		/* After the first step any further non-conditional order is good,
		 * regardless of previous USE_NEXT settings. The case of cur and next or
		 * their respective stations being equal is handled elsewhere. */
		SetBit(flags, USE_NEXT);

		if (next->IsType(OT_CONDITIONAL)) {
			const Order *skip_to = this->vehicle->orders.list->GetNextDecisionNode(
					this->vehicle->orders.list->GetOrderAt(next->GetConditionSkipToOrder()), num_hops);
			if (skip_to != NULL && num_hops < this->vehicle->orders.list->GetNumOrders()) {
				/* Make copies of capacity tracking lists. There is potential
				 * for optimization here: If the vehicle never refits we don't
				 * need to copy anything. Also, if we've seen the branched link
				 * before we don't need to branch at all. */
				LinkRefresher branch(*this);
				branch.RefreshLinks(cur, skip_to, flags, num_hops + 1);
			}
		}

		/* Reassign next with the following stop. This can be a station or a
		 * depot.*/
		next = this->vehicle->orders.list->GetNextDecisionNode(
				this->vehicle->orders.list->GetNext(next), num_hops++);
	}
	return next;
}

/**
 * Refresh link stats for the given pair of orders.
 * @param cur Last stop where the consist could interact with cargo.
 * @param next Next order to be processed.
 */
void LinkRefresher::RefreshStats(const Order *cur, const Order *next)
{
	StationID next_station = next->GetDestination();
	Station *st = Station::GetIfValid(cur->GetDestination());
	if (st != NULL && next_station != INVALID_STATION && next_station != st->index) {
		for (CapacitiesMap::const_iterator i = this->capacities.begin(); i != this->capacities.end(); ++i) {
			/* Refresh the link and give it a minimum capacity. */

			if (i->second == 0) continue;
			CargoID c = i->first;

			/* If not allowed to merge link graphs, make sure the stations are
			 * already in the same link graph. */
			if (!this->allow_merge && st->goods[c].link_graph != Station::Get(next_station)->goods[c].link_graph) {
				continue;
			}

			/* A link is at least partly restricted if a
			 * vehicle can't load at its source. */
			IncreaseStats(st, c, next_station, i->second,
					(cur->GetLoadType() & OLFB_NO_LOAD) == 0 ? LinkGraph::REFRESH_UNRESTRICTED : LinkGraph::REFRESH_RESTRICTED);
		}
	}
}

/**
 * Iterate over orders starting at \a cur and \a next and refresh links
 * associated with them. \a cur and \a next can be equal. If they're not they
 * must be "neigbours" in their order list, which means \a next must be directly
 * reachable from \a cur without passing any further OT_GOTO_STATION or
 * OT_IMPLICIT orders in between.
 * @param cur Current order being evaluated.
 * @param next Next order to be checked.
 * @param flags RefreshFlags to give hints about the previous link and state carried over from that.
 * @param num_hops Number of hops already taken by recursive calls to this method.
 */
void LinkRefresher::RefreshLinks(const Order *cur, const Order *next, uint8 flags, uint num_hops)
{
	while (next != NULL) {

		/* If the refit cargo is CT_AUTO_REFIT, we're optimistic and assume the
		 * cargo will stay the same. The point of this method is to avoid
		 * deadlocks due to vehicles waiting for cargo that isn't being routed,
		 * yet. That situation will not occur if the vehicle is actually
		 * carrying a different cargo in the end. */
		if ((next->IsType(OT_GOTO_DEPOT) || next->IsType(OT_GOTO_STATION)) &&
				next->IsRefit() && !next->IsAutoRefit()) {
			SetBit(flags, WAS_REFIT);
			this->HandleRefit(next);
		}

		/* Only reset the refit capacities if the "previous" next is a station,
		 * meaning that either the vehicle was refit at the previous station or
		 * it wasn't at all refit during the current hop. */
		if (HasBit(flags, WAS_REFIT) && (next->IsType(OT_GOTO_STATION) || next->IsType(OT_IMPLICIT))) {
			SetBit(flags, RESET_REFIT);
		} else {
			ClrBit(flags, RESET_REFIT);
		}

		next = this->PredictNextOrder(cur, next, flags, num_hops);
		if (next == NULL) break;
		Hop hop(cur->index, next->index, this->cargo);
		if (this->seen_hops->find(hop) != this->seen_hops->end()) {
			break;
		} else {
			this->seen_hops->insert(hop);
		}

		/* Don't use the same order again, but choose a new one in the next round. */
		ClrBit(flags, USE_NEXT);

		/* Skip resetting and link refreshing if next order won't do anything with cargo. */
		if (!next->IsType(OT_GOTO_STATION) && !next->IsType(OT_IMPLICIT)) continue;

		if (HasBit(flags, RESET_REFIT)) {
			this->ResetRefit();
			ClrBit(flags, RESET_REFIT);
			ClrBit(flags, WAS_REFIT);
		}

		if (cur->IsType(OT_GOTO_STATION) || cur->IsType(OT_IMPLICIT)) {
			if (cur->CanLeaveWithCargo(HasBit(flags, HAS_CARGO))) {
				SetBit(flags, HAS_CARGO);
				this->RefreshStats(cur, next);
			} else {
				ClrBit(flags, HAS_CARGO);
			}
		}

		/* "cur" is only assigned here if the stop is a station so that
		 * whenever stats are to be increased two stations can be found. */
		cur = next;
	}
}
