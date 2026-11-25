use Memoize; my $calls = 0; sub slow { $calls++; $_[0] * 2 } memoize("slow"); slow(2); slow(2); print slow(2), $calls, "\n";
