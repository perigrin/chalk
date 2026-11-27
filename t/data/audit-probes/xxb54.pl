our @g=(1,2,3); sub z { @g = () } my $n = 0; for my $x (@g) { $n++; z() if $n == 1 } print "$n\n";
