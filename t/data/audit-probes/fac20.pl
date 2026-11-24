my %a=(k=>1); my %b=(k=>2); my $t=@ARGV?0:1; my %c = $t ? %a : %b; $c{k}=9; print "$a{k}$b{k}\n";
