sub f { $_[0]=9 } my %h=(a=>1); f($h{a}); f($h{b}); print join(",",map{"$_=$h{$_}"}sort keys %h),"\n";
