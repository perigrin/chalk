our @g = (1,2); sub f { local $" = "-"; "@g" } my $s = f() . "@g"; print "$s\n";
