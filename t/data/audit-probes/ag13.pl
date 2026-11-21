our $g = 0; sub f { $g = $_[0] + 1; $_[0] } my @a = [f(1), $g, f(0), $g]; print "@{$a[0]}\n";
