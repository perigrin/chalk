# A shop's inventory: products in a hash of hashes, orders checked and
# applied with die and try, restocking, and an invoice with taxes and a
# discount, printed with printf.
use v5.42;

my %stock = (
    widget  => { price => 2.50,  qty => 100, taxable => 1 },
    gadget  => { price => 12.99, qty => 15,  taxable => 1 },
    gizmo   => { price => 7.25,  qty => 0,   taxable => 1 },
    manual  => { price => 4.00,  qty => 40,  taxable => 0 },
);
my $tax_rate = 0.08;

sub order (%items) {
    for my $name (sort keys %items) {
        die "unknown product '$name'\n" unless exists $stock{$name};
        die "bad quantity $items{$name} for $name\n" unless $items{$name} > 0;
        die "only $stock{$name}{qty} $name left, $items{$name} wanted\n" if $stock{$name}{qty} < $items{$name};
    }
    $stock{$_}{qty} -= $items{$_} for sort keys %items;
    return invoice(%items);
}

sub invoice (%items) {
    my @lines;
    my ($subtotal, $tax) = (0, 0);
    for my $name (sort keys %items) {
        my $p = $stock{$name};
        my $amount = $p->{price} * $items{$name};
        $subtotal += $amount;
        $tax += $amount * $tax_rate if $p->{taxable};
        push @lines, sprintf("  %-8s %3d x %6.2f = %8.2f%s", $name, $items{$name}, $p->{price}, $amount, $p->{taxable} ? "" : " (no tax)");
    }
    my $discount = $subtotal >= 100 ? 0.05 * $subtotal : 0;
    push @lines, sprintf("  %-28s %8.2f", "subtotal", $subtotal);
    push @lines, sprintf("  %-28s %8.2f", "discount 5%", -$discount) if $discount;
    push @lines, sprintf("  %-28s %8.2f", "tax", $tax);
    push @lines, sprintf("  %-28s %8.2f", "total", $subtotal - $discount + $tax);
    return join("\n", @lines) . "\n";
}

sub restock ($name, $qty) {
    $stock{$name}{qty} += $qty;
    return $stock{$name}{qty};
}

sub report () {
    for my $name (sort { $stock{$a}{qty} <=> $stock{$b}{qty} || $a cmp $b } keys %stock) {
        my $q = $stock{$name}{qty};
        printf "  %-8s %4d %s\n", $name, $q, $q == 0 ? "OUT" : $q < 20 ? "low" : "";
    }
}

my @orders = (
    { widget => 10, manual => 2 },
    { gadget => 8, widget => 20 },
    { gizmo => 1 },
    { gadget => 8 },
    { sprocket => 3 },
    { widget => -1 },
);
my $n = 0;
for my $o (@orders) {
    $n++;
    try {
        print "order $n:\n", order($o->%*);
    } catch ($e) {
        print "order $n refused: $e";
    }
}
say "gizmos now ", restock(gizmo => 5);
print "order 7:\n", order(gizmo => 5, manual => 38);
say "stock:";
report();
my $value = 0;
$value += $stock{$_}{price} * $stock{$_}{qty} for sort keys %stock;
printf "stock is worth %.2f\n", $value;
