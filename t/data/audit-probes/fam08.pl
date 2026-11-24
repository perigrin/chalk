my $s="axx"; { local $/="x"; chomp $s; } print "$s\n";
