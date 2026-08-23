package com.chesscoach.android.ui.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.billing.ReviewEntitlementStore
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedCard
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import kotlinx.coroutines.launch

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * Native purchase screen for the Review plan -- a one-time, non-consumable
 * unlock (Android's only IAP; no Pro plan, no coach here). Port of iOS's
 * `ReviewUnlockPaywallView`, minus the Pro-subscriber reassurance note and
 * the LLM-coach messaging, since neither applies on Android.
 */
@Composable
fun ReviewUnlockPaywallScreen(store: ReviewEntitlementStore, onClose: () -> Unit) {
    val hasReviewAccess by store.hasReviewAccess.collectAsState()
    var lifetimePackage by remember { mutableStateOf<Package?>(null) }
    var isLoadingOfferings by remember { mutableStateOf(true) }
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }

    LaunchedEffect(Unit) {
        val offerings = store.loadOfferings()
        lifetimePackage = offerings?.current?.availablePackages?.firstOrNull { it.packageType == PackageType.LIFETIME }
        isLoadingOfferings = false
    }

    LaunchedEffect(hasReviewAccess) {
        if (hasReviewAccess) onClose()
    }

    ThemedScreen(title = "Review Plan", onBack = onClose) {
        Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 24.dp)) {
            Icon(
                Icons.AutoMirrored.Filled.TrendingUp,
                contentDescription = null,
                tint = ChessCoachTheme.accent,
                modifier = Modifier.size(40.dp),
            )
            Spacer(Modifier.padding(top = 10.dp))
            Text(
                "One-time purchase. Unlock full move analysis beyond move 6 -- once, yours forever.",
                color = ChessCoachTheme.mutedText,
                fontSize = 14.sp,
                textAlign = TextAlign.Start,
            )

            Spacer(Modifier.padding(top = 20.dp))
            ThemedCard {
                FeatureRow(Icons.Filled.CheckCircle, "Full move-by-move classification and best-move suggestions, beyond move 6")
                Spacer(Modifier.padding(top = 10.dp))
                FeatureRow(Icons.Filled.AllInclusive, "Every game you've played or ever will -- no subscription")
                Spacer(Modifier.padding(top = 10.dp))
                FeatureRow(Icons.Filled.Payments, "Pay once, own it forever")
            }

            Spacer(Modifier.padding(top = 20.dp))
            when {
                isLoadingOfferings -> CircularProgressIndicator(color = ChessCoachTheme.accent, modifier = Modifier.padding(top = 12.dp))
                lifetimePackage != null -> {
                    val pkg = lifetimePackage!!
                    ThemedCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "Review Plan",
                                color = ChessCoachTheme.text,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                pkg.product.price.formatted,
                                color = ChessCoachTheme.text,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                    Spacer(Modifier.padding(top = 10.dp))
                    ThemedPrimaryButton(
                        text = if (isPurchasing) "Processing..." else "Unlock Full Review",
                        enabled = !isPurchasing,
                        onClick = {
                            val act = activity ?: return@ThemedPrimaryButton
                            errorMessage = null
                            isPurchasing = true
                            scope.launch {
                                store.purchase(act, pkg).onFailure { errorMessage = it.message }
                                isPurchasing = false
                            }
                        },
                    )
                }
                else -> Text(
                    "Not available right now, try again shortly.",
                    color = ChessCoachTheme.mutedText,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }

            errorMessage?.let {
                Spacer(Modifier.padding(top = 10.dp))
                Text(it, color = ChessCoachTheme.accent2, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }

            Spacer(Modifier.padding(top = 16.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !isRestoring) {
                        errorMessage = null
                        isRestoring = true
                        scope.launch {
                            store.restore()
                                .onSuccess { if (!store.hasReviewAccess.value) errorMessage = "No previous purchase found for this Google account." }
                                .onFailure { errorMessage = it.message }
                            isRestoring = false
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (isRestoring) "Restoring..." else "Restore Purchases",
                    color = ChessCoachTheme.mutedText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                )
            }

            Spacer(Modifier.padding(top = 20.dp))
            Text(
                "Your purchase helps us keep building free features for everyone.",
                color = ChessCoachTheme.mutedText,
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 6.dp))
            Text(
                "One-time purchase. No subscription, no renewal. Payment is charged to your Google Play account at confirmation of purchase.",
                color = ChessCoachTheme.faintText,
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                LegalLink("Terms of Use", "https://chesscoach.im/terms")
                Spacer(Modifier.width(16.dp))
                LegalLink("Privacy Policy", "https://chesscoach.im/privacy")
            }
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = ChessCoachTheme.accent2, modifier = Modifier.size(18.dp).padding(top = 2.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, color = ChessCoachTheme.text, fontSize = 14.sp)
    }
}

@Composable
private fun LegalLink(text: String, url: String) {
    val context = LocalContext.current
    Text(
        text,
        color = ChessCoachTheme.accent2,
        fontSize = 11.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) },
    )
}
