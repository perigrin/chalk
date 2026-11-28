our $x = 1; sub f :lvalue { $x } { local $x = 2; my $r = \f(); $$r = 5; print $x } print "$x\n";
