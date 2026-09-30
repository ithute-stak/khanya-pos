import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/auth/data/auth_repository.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, required this.onBackToSignIn});

  final VoidCallback onBackToSignIn;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _businessSlug = TextEditingController();
  final _branchName = TextEditingController(text: 'Main Branch');
  final _branchCode = TextEditingController(text: 'MAIN');
  final _branchLocation = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;
  OnboardingSubmission? _submission;
  bool _slugEdited = false;

  @override
  void initState() {
    super.initState();
    _businessName.addListener(_suggestSlug);
    _businessSlug.addListener(() {
      if (_businessSlug.text.isNotEmpty && _businessSlug.text != _slugify(_businessName.text)) {
        _slugEdited = true;
      }
    });
  }

  String _slugify(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .substring(0, value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '').length.clamp(0, 80));

  void _suggestSlug() {
    if (_slugEdited) return;
    final slug = _businessName.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safe = slug.length > 80 ? slug.substring(0, 80) : slug;
    if (_businessSlug.text != safe) {
      _businessSlug.value = TextEditingValue(
        text: safe,
        selection: TextSelection.collapsed(offset: safe.length),
      );
    }
  }

  @override
  void dispose() {
    _businessName.removeListener(_suggestSlug);
    for (final controller in [
      _businessName,
      _businessSlug,
      _branchName,
      _branchCode,
      _branchLocation,
      _ownerName,
      _email,
      _phone,
      _password,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthRepository>().signup(
            businessName: _businessName.text,
            businessSlug: _businessSlug.text,
            branchName: _branchName.text,
            branchCode: _branchCode.text,
            branchLocation: _branchLocation.text,
            ownerName: _ownerName.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
          );
      if (!mounted) return;
      setState(() => _submission = result);
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      setState(() => _error = detail ?? 'We could not submit your application. Please try again.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not submit your application. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submission != null) {
      return _SubmittedView(
        submission: _submission!,
        onBackToSignIn: widget.onBackToSignIn,
      );
    }

    return Scaffold(
      body: KhanyaBrandedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: _submitting ? null : widget.onBackToSignIn,
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'Back to sign in',
                        ),
                        const SizedBox(width: 8),
                        const KhanyaBrandTitle(),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Open a Khanya account',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: KhanyaBrand.navy,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tell us about the business and the owner. Your workspace will be created in pending status and activated after review.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    Form(
                      key: _formKey,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _SectionTitle('Business details'),
                              const SizedBox(height: 14),
                              _twoColumn(
                                TextFormField(
                                  controller: _businessName,
                                  enabled: !_submitting,
                                  decoration: const InputDecoration(
                                    labelText: 'Business name',
                                    prefixIcon: Icon(Icons.storefront_outlined),
                                  ),
                                  validator: _required,
                                ),
                                TextFormField(
                                  controller: _businessSlug,
                                  enabled: !_submitting,
                                  decoration: const InputDecoration(
                                    labelText: 'Business ID / slug',
                                    helperText: 'Lowercase letters, numbers and hyphens',
                                    prefixIcon: Icon(Icons.link_outlined),
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (text.length < 3) return 'Use at least 3 characters';
                                    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$').hasMatch(text)) {
                                      return 'Use lowercase letters, numbers and hyphens only';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 18),
                              const _SectionTitle('Main branch'),
                              const SizedBox(height: 14),
                              _twoColumn(
                                TextFormField(
                                  controller: _branchName,
                                  enabled: !_submitting,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch name',
                                    prefixIcon: Icon(Icons.business_outlined),
                                  ),
                                  validator: _required,
                                ),
                                TextFormField(
                                  controller: _branchCode,
                                  enabled: !_submitting,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch code',
                                    prefixIcon: Icon(Icons.tag_outlined),
                                  ),
                                  validator: _required,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _branchLocation,
                                enabled: !_submitting,
                                decoration: const InputDecoration(
                                  labelText: 'Branch location (optional)',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const _SectionTitle('Business owner'),
                              const SizedBox(height: 14),
                              _twoColumn(
                                TextFormField(
                                  controller: _ownerName,
                                  enabled: !_submitting,
                                  decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: _required,
                                ),
                                TextFormField(
                                  controller: _email,
                                  enabled: !_submitting,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Email address',
                                    prefixIcon: Icon(Icons.email_outlined),
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (!text.contains('@') || !text.contains('.')) return 'Enter a valid email address';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _phone,
                                enabled: !_submitting,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone number (optional)',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const _SectionTitle('Security'),
                              const SizedBox(height: 14),
                              _twoColumn(
                                TextFormField(
                                  controller: _password,
                                  enabled: !_submitting,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) => (value?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
                                ),
                                TextFormField(
                                  controller: _confirmPassword,
                                  enabled: !_submitting,
                                  obscureText: _obscurePassword,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm password',
                                    prefixIcon: Icon(Icons.lock_reset_outlined),
                                  ),
                                  validator: (value) => value != _password.text ? 'Passwords do not match' : null,
                                ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: _submitting ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.send_outlined),
                                label: Text(_submitting ? 'Submitting…' : 'Submit for approval'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _twoColumn(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(children: [first, const SizedBox(height: 14), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'This field is required' : null;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: KhanyaBrand.navy,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _SubmittedView extends StatelessWidget {
  const _SubmittedView({required this.submission, required this.onBackToSignIn});

  final OnboardingSubmission submission;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KhanyaBrandedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(Icons.mark_email_read_outlined, size: 58, color: KhanyaBrand.forest),
                        const SizedBox(height: 20),
                        Text(
                          'Application submitted',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: KhanyaBrand.navy,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          submission.message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          submission.businessName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text('Status: Pending approval'),
                        const SizedBox(height: 26),
                        FilledButton.icon(
                          onPressed: onBackToSignIn,
                          icon: const Icon(Icons.login_outlined),
                          label: const Text('Back to sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
