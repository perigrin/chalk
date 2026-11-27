sub f { my ($p) = @_; $p } my $n = "f"; my $x = 3; { no strict 'refs'; print &$n($x), &{"main::$n"}($x), "\n"; }
