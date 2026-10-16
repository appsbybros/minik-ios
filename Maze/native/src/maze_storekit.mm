// Minik Maze for iOS: the permanent unlock (the non-consumable "full_game_unlock") through the App Store.
// ios/maze_services_ios.gd creates MazeStoreKit and listens to its signals; Android's counterpart is
// MazeServices.kt (Play Billing). StoreKit 1 keeps this in Objective-C++, which godot-cpp can build.
//
// Signals (always deferred to the next frame, on Godot's thread):
//   owned                    a purchase or a restore delivered the unlock
//   pending                  Ask to Buy: waiting for the parent's approval
//   price_changed(price)     the localized App Store price is known
//   purchase_failed(reason)  "cancelled" or "failed"
//   restore_finished(found)  a restore ended; found tells whether the unlock was among the purchases

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

#include <gdextension_interface.h>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

// SKPaymentQueue and SKProductsRequest are deprecated in favour of the Swift-only StoreKit 2; Apple still
// supports them.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void maze_emit(uint64_t p_owner, const char *p_signal) {
	if (godot::Object *owner = p_owner ? godot::ObjectDB::get_instance(p_owner) : nullptr) {
		owner->call_deferred("emit_signal", godot::StringName(p_signal));
	}
}

static void maze_emit(uint64_t p_owner, const char *p_signal, const godot::Variant &p_value) {
	if (godot::Object *owner = p_owner ? godot::ObjectDB::get_instance(p_owner) : nullptr) {
		owner->call_deferred("emit_signal", godot::StringName(p_signal), p_value);
	}
}

@interface MazeStoreObserver : NSObject <SKPaymentTransactionObserver, SKProductsRequestDelegate>
@property(nonatomic) uint64_t owner;
@property(nonatomic, copy) NSString *productId;
@property(nonatomic, strong) SKProduct *product;
@property(nonatomic, strong) SKProductsRequest *request;
@property(nonatomic, copy) NSString *price;
@property(nonatomic) BOOL restoredProduct;
@end

@implementation MazeStoreObserver

- (void)requestProduct {
	if (self.request != nil || self.product != nil || self.productId.length == 0) {
		return;
	}
	self.request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:self.productId]];
	self.request.delegate = self;
	[self.request start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
	for (SKProduct *item in response.products) {
		if ([item.productIdentifier isEqualToString:self.productId]) {
			self.product = item;
		}
	}
	if (self.product != nil) {
		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
		formatter.numberStyle = NSNumberFormatterCurrencyStyle;
		formatter.locale = self.product.priceLocale;
		self.price = [formatter stringFromNumber:self.product.price] ?: @"";
		maze_emit(self.owner, "price_changed", godot::String::utf8(self.price.UTF8String));
	}
}

- (void)requestDidFinish:(SKRequest *)request {
	self.request = nil;
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
	// No network or no product yet: the next buy() asks again.
	self.request = nil;
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
	for (SKPaymentTransaction *transaction in transactions) {
		BOOL ours = [transaction.payment.productIdentifier isEqualToString:self.productId];
		switch (transaction.transactionState) {
			case SKPaymentTransactionStatePurchased:
			case SKPaymentTransactionStateRestored:
				if (ours) {
					// Also a purchase that completes during a restore: the restore must not then report "not found".
					self.restoredProduct = YES;
					maze_emit(self.owner, "owned");
				}
				[queue finishTransaction:transaction];
				break;
			case SKPaymentTransactionStateFailed: {
				if (ours) {
					BOOL cancelled = [transaction.error.domain isEqualToString:SKErrorDomain] && transaction.error.code == SKErrorPaymentCancelled;
					maze_emit(self.owner, "purchase_failed", godot::String(cancelled ? "cancelled" : "failed"));
				}
				[queue finishTransaction:transaction];
				break;
			}
			case SKPaymentTransactionStateDeferred:
				if (ours) {
					maze_emit(self.owner, "pending");
				}
				break;
			default:
				break;
		}
	}
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
	maze_emit(self.owner, "restore_finished", (bool)self.restoredProduct);
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
	BOOL cancelled = [error.domain isEqualToString:SKErrorDomain] && error.code == SKErrorPaymentCancelled;
	maze_emit(self.owner, "purchase_failed", godot::String(cancelled ? "cancelled" : "failed"));
}

@end

class MazeStoreKit : public godot::Object {
	GDCLASS(MazeStoreKit, godot::Object);

	MazeStoreObserver *observer = nil;

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("start", "product_id"), &MazeStoreKit::start);
		godot::ClassDB::bind_method(godot::D_METHOD("buy"), &MazeStoreKit::buy);
		godot::ClassDB::bind_method(godot::D_METHOD("restore"), &MazeStoreKit::restore);
		godot::ClassDB::bind_method(godot::D_METHOD("can_buy"), &MazeStoreKit::can_buy);
		godot::ClassDB::bind_method(godot::D_METHOD("get_price"), &MazeStoreKit::get_price);
		ADD_SIGNAL(godot::MethodInfo("owned"));
		ADD_SIGNAL(godot::MethodInfo("pending"));
		ADD_SIGNAL(godot::MethodInfo("price_changed", godot::PropertyInfo(godot::Variant::STRING, "price")));
		ADD_SIGNAL(godot::MethodInfo("purchase_failed", godot::PropertyInfo(godot::Variant::STRING, "reason")));
		ADD_SIGNAL(godot::MethodInfo("restore_finished", godot::PropertyInfo(godot::Variant::BOOL, "found")));
	}

public:
	/// Listens to the App Store from now on (purchases that finished while the app was closed arrive
	/// here too) and asks for the product's price.
	void start(const godot::String &p_product_id) {
		if (observer == nil) {
			observer = [[MazeStoreObserver alloc] init];
			observer.owner = get_instance_id();
			observer.productId = [NSString stringWithUTF8String:p_product_id.utf8().get_data()];
			[[SKPaymentQueue defaultQueue] addTransactionObserver:observer];
		}
		[observer requestProduct];
	}

	bool can_buy() {
		if (observer == nil) {
			return false;
		}
		if (observer.product == nil) {
			[observer requestProduct];
			return false;
		}
		return [SKPaymentQueue canMakePayments];
	}

	void buy() {
		if (!can_buy()) {
			maze_emit(get_instance_id(), "purchase_failed", godot::String("failed"));
			return;
		}
		[[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:observer.product]];
	}

	void restore() {
		if (observer == nil) {
			maze_emit(get_instance_id(), "purchase_failed", godot::String("failed"));
			return;
		}
		observer.restoredProduct = NO;
		[[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
	}

	godot::String get_price() const {
		return observer != nil && observer.price != nil ? godot::String::utf8(observer.price.UTF8String) : godot::String();
	}

	~MazeStoreKit() {
		if (observer != nil) {
			observer.owner = 0;
			[[SKPaymentQueue defaultQueue] removeTransactionObserver:observer];
		}
	}
};

static void initialize_maze_storekit(godot::ModuleInitializationLevel p_level) {
	if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(MazeStoreKit);
}

static void uninitialize_maze_storekit(godot::ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT maze_storekit_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_maze_storekit);
	init_obj.register_terminator(uninitialize_maze_storekit);
	init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
