use Scalar::Util qw(reftype); my $x = 1; my $r = \$x; my $rr = \$r; my $q = qr/a+/; print join(" ", reftype({}), reftype(bless [], "K"), reftype($rr), ref($rr), reftype($q), reftype(5) // "u"), "\n";
