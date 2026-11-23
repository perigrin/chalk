my %h=(a=>1); for my $v ($h{a},$h{b}) { $v//=5 } print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
