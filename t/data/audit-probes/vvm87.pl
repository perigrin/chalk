our $x = 1; { no strict 'refs'; my $n = "x"; local ${$n} = 2; print $$n } print "$x\n";
