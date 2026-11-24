my $i=0; sub n { ++$i } my %h=(n()=>n()); print join("",%h),"\n";
