package T; sub TIESCALAR { bless [0], shift } sub FETCH { $_[0][0]++ } sub STORE { } package main; tie my $x, "T"; my $a = $x; my $b = $x; print "$a $b\n";
