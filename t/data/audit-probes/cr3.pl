use Scalar::Util qw(blessed reftype); my $o = []; my $a = blessed($o) // "u"; my $t = reftype($o); bless $o, "K"; print "$a $t ", blessed($o), " ", reftype($o), "\n";
