my %h; my $c=1; ($c ? $h{a} : $h{b}) = 9; print join("",sort keys %h),"\n";
