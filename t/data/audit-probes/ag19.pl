our $g = 0; sub f { $g = $_[0] + 1; $_[0] } my $v = $g; print $v, f(1), $g, "\n";
