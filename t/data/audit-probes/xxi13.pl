sub f { "f" } my $n = "f"; { no strict 'refs'; print &$n, "\n"; }
