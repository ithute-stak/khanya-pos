import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/growth/data/growth_repository.dart';

class CheckoutBenefits {
  const CheckoutBenefits({
    required this.totalMinor,
    required this.discountMinor,
    this.promotionCode,
    this.loyaltyPoints = 0,
  });

  final int totalMinor;
  final int discountMinor;
  final String? promotionCode;
  final int loyaltyPoints;
}

Future<CheckoutBenefits?> showCheckoutBenefitsDialog(
  BuildContext context, {
  required int subtotalMinor,
  String? customerId,
}) {
  return showDialog<CheckoutBenefits>(
    context: context,
    builder: (_) => _CheckoutBenefitsDialog(
      repository: context.read<GrowthRepository>(),
      subtotalMinor: subtotalMinor,
      customerId: customerId,
    ),
  );
}

class _CheckoutBenefitsDialog extends StatefulWidget {
  const _CheckoutBenefitsDialog({
    required this.repository,
    required this.subtotalMinor,
    required this.customerId,
  });

  final GrowthRepository repository;
  final int subtotalMinor;
  final String? customerId;

  @override
  State<_CheckoutBenefitsDialog> createState() => _CheckoutBenefitsDialogState();
}

class _CheckoutBenefitsDialogState extends State<_CheckoutBenefitsDialog> {
  final _promotion = TextEditingController();
  final _points = TextEditingController(text: '0');
  PromotionPreview? _promotionPreview;
  LoyaltyProgramSummary? _program;
  LoyaltyCustomerSummary? _loyalty;
  String? _message;
  bool _loading = true;
  bool _applyingPromotion = false;

  @override
  void initState() {
    super.initState();
    _loadLoyalty();
  }

  @override
  void dispose() {
    _promotion.dispose();
    _points.dispose();
    super.dispose();
  }

  Future<void> _loadLoyalty() async {
    try {
      final program = await widget.repository.loyaltyProgram();
      LoyaltyCustomerSummary? loyalty;
      if (widget.customerId != null && program.isActive) {
        loyalty = await widget.repository.customerLoyalty(widget.customerId!);
      }
      if (!mounted) return;
      setState(() {
        _program = program;
        _loyalty = loyalty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Rewards are unavailable offline. You can continue without them.';
      });
    }
  }

  Future<void> _applyPromotion() async {
    final code = _promotion.text.trim();
    if (code.isEmpty) {
      setState(() {
        _promotionPreview = null;
        _message = null;
      });
      return;
    }
    setState(() {
      _applyingPromotion = true;
      _message = null;
    });
    try {
      final preview = await widget.repository.previewPromotion(
        code: code,
        subtotalMinor: widget.subtotalMinor,
      );
      if (!mounted) return;
      setState(() {
        _promotionPreview = preview;
        _applyingPromotion = false;
        _message = 'Promotion applied: ${Loti.formatMinor(preview.discountMinor)} off.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _promotionPreview = null;
        _applyingPromotion = false;
        _message = error is StateError ? error.message.toString() : 'Promotion could not be applied.';
      });
    }
  }

  CheckoutBenefits _result() {
    final afterPromotion = _promotionPreview?.totalMinor ?? widget.subtotalMinor;
    var points = int.tryParse(_points.text.trim()) ?? 0;
    points = math.max(0, points);
    final program = _program;
    final loyalty = _loyalty;
    if (program == null || !program.isActive || loyalty == null) points = 0;
    if (loyalty != null) points = math.min(points, loyalty.pointsBalance);

    final pointValueMinor = program == null ? 0 : ScaledDecimal.toMinor(program.currencyPerPoint);
    if (pointValueMinor <= 0) points = 0;
    if (pointValueMinor > 0) points = math.min(points, afterPromotion ~/ pointValueMinor);
    if (program != null && points > 0 && points < program.minRedeemPoints) points = 0;

    final loyaltyDiscount = points * pointValueMinor;
    final total = math.max(0, afterPromotion - loyaltyDiscount);
    return CheckoutBenefits(
      totalMinor: total,
      discountMinor: widget.subtotalMinor - total,
      promotionCode: _promotionPreview == null ? null : _promotion.text.trim().toUpperCase(),
      loyaltyPoints: points,
    );
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    final loyalty = _loyalty;
    final afterPromotion = _promotionPreview?.totalMinor ?? widget.subtotalMinor;
    return AlertDialog(
      title: const Text('Promotion & rewards'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Basket total: ${Loti.formatMinor(widget.subtotalMinor)}'),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promotion,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Promotion code',
                        hintText: 'Optional',
                      ),
                      onSubmitted: (_) => _applyPromotion(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: _applyingPromotion ? null : _applyPromotion,
                    child: _applyingPromotion
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LinearProgressIndicator()
              else if (program?.isActive == true && loyalty != null) ...[
                Text(
                  '${program!.name}: ${loyalty.pointsBalance} points available',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Points to redeem',
                    helperText:
                        'Minimum ${program.minRedeemPoints}; 1 point = M${program.currencyPerPoint}',
                  ),
                ),
              ] else if (widget.customerId == null)
                const Text('Select a customer to earn or redeem loyalty points.')
              else
                const Text('Customer loyalty is not active for this business.'),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              Text(
                'Current payable before points: ${Loti.formatMinor(afterPromotion)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel checkout')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            CheckoutBenefits(totalMinor: widget.subtotalMinor, discountMinor: 0),
          ),
          child: const Text('No benefits'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
