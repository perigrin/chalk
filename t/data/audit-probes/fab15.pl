my $s="x=1,y=2"; my %h=$s=~/(\w)=(\d)/g; print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
