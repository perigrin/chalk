use feature "current_sub"; our $x = 1; sub rd { $x } my $c = sub { local $x = $x + 1; $_[0] ? __SUB__->($_[0]-1) : rd() }; print $c->(2), rd(), "\n";
