my %h=(a=>1,b=>2); my @v=values %h; $_=0 for @v; print join("",map{$h{$_}}sort keys %h),"\n";
