package com.keel.manager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.keel.manager.R
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelChip
import com.keel.manager.ui.components.KeelTextField
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelRadii
import com.keel.manager.ui.theme.KeelType
import kotlinx.coroutines.launch

/**
 * Onboarding — 2 steps, shown once, never again.
 * Step 1: your name + role. Step 2: your organization.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen(viewModel: KeelViewModel) {
    var step by remember { mutableStateOf(0) }
    var name by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("") }
    var orgName by remember { mutableStateOf("") }
    var orgKind by remember { mutableStateOf("Studio") }
    val scope = rememberCoroutineScope()

    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp, vertical = 48.dp),
    ) {
        Column(Modifier.fillMaxSize()) {
            // App icon tile — the same anchor as the launcher icon.
            Box(
                modifier = Modifier
                    .size(92.dp)
                    .clip(RoundedCornerShape(KeelRadii.IconTile))
                    .background(
                        Brush.linearGradient(
                            listOf(KeelColors.TealGradientTop, KeelColors.TealGradientBottom),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    painterResource(R.drawable.ic_anchor),
                    contentDescription = "Keel",
                    tint = Color.White,
                    modifier = Modifier.size(50.dp),
                )
            }
            Spacer(Modifier.height(24.dp))
            Text(
                if (step == 0) "Welcome to Keel" else "Your organization",
                style = KeelType.Display,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                if (step == 0) "Your work, in order. Keel keeps everything on this phone — no account, no server."
                else "One organization at a time. You can add more later from Settings.",
                style = KeelType.Body,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(32.dp))

            if (step == 0) {
                Text("Your name", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                KeelTextField(value = name, onValueChange = { name = it }, placeholder = "e.g. Aby Bijo")
                Spacer(Modifier.height(20.dp))
                Text("Your role", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                KeelTextField(value = role, onValueChange = { role = it }, placeholder = "e.g. Manager")
            } else {
                Text("Organization name", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                KeelTextField(value = orgName, onValueChange = { orgName = it }, placeholder = "e.g. Northwind Studio")
                Spacer(Modifier.height(20.dp))
                Text("What kind is it?", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                val kinds = listOf("Studio", "Company", "Club", "Family", "Other")
                androidx.compose.foundation.layout.FlowRow(
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                ) {
                    for (kind in kinds) {
                        KeelChip(label = kind, selected = orgKind == kind, onClick = { orgKind = kind })
                    }
                }
            }

            Spacer(Modifier.weight(1f))
            KeelButton(
                label = if (step == 0) "Continue" else "Start using Keel",
                onClick = {
                    if (step == 0) {
                        if (name.isBlank()) return@KeelButton
                        step = 1
                    } else {
                        if (orgName.isBlank()) return@KeelButton
                        scope.launch {
                            viewModel.repository.saveProfile(name, role)
                            val org = viewModel.repository.createOrganization(orgName, orgKind)
                            viewModel.settingsStore.setActiveOrgId(org.id)
                            viewModel.settingsStore.setOnboardingDone(true)
                        }
                    }
                },
                enabled = if (step == 0) name.isNotBlank() else orgName.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            if (step == 1) {
                KeelButton(
                    label = "Back",
                    onClick = { step = 0 },
                    primary = false,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
