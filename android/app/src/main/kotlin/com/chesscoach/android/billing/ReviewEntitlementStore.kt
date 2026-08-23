package com.chesscoach.android.billing

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine

private const val REVIEW_ENTITLEMENT_ID = "review_lifetime"

/**
 * Wraps the RevenueCat Purchases SDK for Android's one purchase: the Review
 * plan (a one-time, non-consumable unlock -- mechanically identical to iOS's
 * `review_lifetime` entitlement, same RevenueCat project). Android ships no
 * Pro plan and no coach, so this is deliberately narrower than iOS's
 * `ProEntitlementStore`: one entitlement, one package, no debug-simulation
 * picker, no server-side gateway parity concern (there's no gateway call to
 * gate here -- see `effectiveHasFullReviewAccess`'s header on iOS for why
 * that's an accepted, already-reviewed tradeoff for this exact entitlement).
 *
 * Constructed once in `ChessCoachApp` and threaded through the nav graph,
 * matching `SavedGameStore`/`EngineProvider`'s existing DI shape.
 */
class ReviewEntitlementStore(private val context: Context) {

    private val _hasReviewAccess = MutableStateFlow(false)
    val hasReviewAccess: StateFlow<Boolean> = _hasReviewAccess.asStateFlow()

    /** Call once at app launch. No-op if already configured. */
    fun configure(apiKey: String) {
        if (Purchases.isConfigured) return
        Purchases.configure(PurchasesConfiguration.Builder(context, apiKey).build())
        refreshCustomerInfo()
    }

    fun refreshCustomerInfo() {
        if (!Purchases.isConfigured) return
        Purchases.sharedInstance.getCustomerInfoWith(
            onError = {},
            onSuccess = { info -> applyEntitlement(info) },
        )
    }

    suspend fun loadOfferings(): Offerings? {
        if (!Purchases.isConfigured) return null
        return suspendCancellableCoroutine { cont ->
            Purchases.sharedInstance.getOfferingsWith(
                onError = { cont.resume(null, null) },
                onSuccess = { offerings -> cont.resume(offerings, null) },
            )
        }
    }

    suspend fun purchase(activity: Activity, pkg: Package): Result<Unit> =
        suspendCancellableCoroutine { cont ->
            Purchases.sharedInstance.purchaseWith(
                PurchaseParams.Builder(activity, pkg).build(),
                onError = { error, userCancelled ->
                    val message = if (userCancelled) "Purchase cancelled." else error.message
                    cont.resume(Result.failure(RuntimeException(message)), null)
                },
                onSuccess = { _, info ->
                    applyEntitlement(info)
                    cont.resume(Result.success(Unit), null)
                },
            )
        }

    suspend fun restore(): Result<Unit> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error -> cont.resume(Result.failure(RuntimeException(error.message)), null) },
            onSuccess = { info ->
                applyEntitlement(info)
                cont.resume(Result.success(Unit), null)
            },
        )
    }

    private fun applyEntitlement(info: CustomerInfo) {
        _hasReviewAccess.value = info.entitlements[REVIEW_ENTITLEMENT_ID]?.isActive == true
    }
}
