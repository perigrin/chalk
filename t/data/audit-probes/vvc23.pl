my $n = 0; *inc = sub { ++$n }; inc(); inc(); print "$n\n";
