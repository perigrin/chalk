my $l=[1,2,3]; my ($h,@t)=@$l; $l->[0]=9; @$l=(@t,$h); print "@$l\n";
