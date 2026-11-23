my %h; for my $i (1..4) { next unless $i%2; $h{$i}=1; last if $i==3 } print join(",",sort keys %h),"\n";
