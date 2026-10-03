import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

abstract class SubscriptionStore {
  bool get supported;
  String get platform;
  Stream<List<PurchaseDetails>> get purchases;
  Future<ProductDetails?> product(String id);
  Future<bool> buy(ProductDetails product);
  Future<void> restore();
  Future<void> complete(PurchaseDetails purchase);
}

class MobileSubscriptionStore implements SubscriptionStore {
  @override
  bool get supported =>
      !kIsWeb &&
      [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform);
  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';
  InAppPurchase get _iap => InAppPurchase.instance;
  @override
  Stream<List<PurchaseDetails>> get purchases =>
      supported ? _iap.purchaseStream : const Stream.empty();
  @override
  Future<ProductDetails?> product(String id) async {
    if (!supported || !await _iap.isAvailable()) return null;
    final response = await _iap.queryProductDetails({id});
    if (response.error != null)
      throw StateError('Mağazaya bağlanılamadı. Tekrar deneyin.');
    for (final product in response.productDetails) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  Future<bool> buy(ProductDetails product) => _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product));
  @override
  Future<void> restore() => _iap.restorePurchases();
  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}
