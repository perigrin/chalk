my %h=(k=>"ab"); sub t { $h{k} =~ tr/a/z/ } my $v=$h{k}; t(); print "$v$h{k}\n";
