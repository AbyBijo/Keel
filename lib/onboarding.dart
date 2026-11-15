import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

const _orgKinds = ['Studio', 'Company', 'Club', 'Family', 'Other'];

/// First launch only: two steps with a stretching pill progress indicator.
/// Never shown again after completion.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _org = TextEditingController();
  String _kind = 'Studio';
  String? _nameError;
  String? _orgError;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_org.text.trim().isEmpty) {
      setState(() => _orgError = 'Give your organization a name.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final settings = ref.read(settingsProvider);
    await repo.saveProfile(
      name: _name.text.trim(),
      role: _role.text.trim(),
    );
    final org = await repo.createOrganization(
      name: _org.text,
      kind: _kind,
    );
    await settings.setActiveOrg(org.id);
    await settings.setOnboardingDone();
    // The root widget rebuilds to Home; the dial animates from zero there.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Pill progress: stretches from step one to two.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: KeelTokens.spring,
                    curve: KeelTokens.easeOut,
                    width: _step == 0 ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _step == 0 ? context.accent : context.line,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: KeelTokens.spring,
                    curve: KeelTokens.easeOut,
                    width: _step == 1 ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _step == 1 ? context.accent : context.line,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: KeelTokens.fade,
                  child: _step == 0 ? _stepOne(context) : _stepTwo(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepOne(BuildContext context) {
    return Column(
      key: const ValueKey('step1'),
      children: [
        const Spacer(),
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF12A0AB), Color(0xFF0B4F66)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B4F66).withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: const Icon(Icons.anchor_rounded, size: 50, color: Colors.white),
        ),
        const SizedBox(height: 28),
        Text(
          'Welcome to Keel',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 36),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Your people, teams and tasks in one calm place. Everything stays on this phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted, fontSize: 15, height: 1.4),
          ),
        ),
        const SizedBox(height: 34),
        KeelTextField(
          controller: _name,
          label: 'What should we call you?',
          hint: 'Your name',
          errorText: _nameError,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continue(),
        ),
        const Spacer(),
        KeelButton(
          label: 'Continue',
          background: context.accent,
          foreground: Colors.white,
          onPressed: _continue,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _continue() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Tell us your name so we can greet you.');
      return;
    }
    setState(() {
      _nameError = null;
      _step = 1;
    });
  }

  Widget _stepTwo(BuildContext context) {
    final firstName = _name.text.trim().split(' ').first;
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          'Hi, $firstName.',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Tell us about the organization you lead right now. You can add more later.',
          style: TextStyle(color: context.muted, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 26),
        KeelTextField(
          controller: _role,
          label: 'Your role',
          hint: 'e.g. Operations Manager',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        KeelTextField(
          controller: _org,
          label: 'Organization',
          hint: 'e.g. Northwind Studio',
          errorText: _orgError,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _finish(),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in _orgKinds)
              ChoiceChip(
                label: Text(kind),
                selected: _kind == kind,
                selectedColor: context.accent,
                labelStyle: TextStyle(
                  color: _kind == kind ? Colors.white : context.ink,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: context.card,
                side: BorderSide(color: context.line),
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const Spacer(),
        KeelButton(
          label: 'Create my workspace',
          background: context.accent,
          foreground: Colors.white,
          onPressed: _finish,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _step = 0),
            child: Text('Back', style: TextStyle(color: context.muted)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
