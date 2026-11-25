my @a=(1,2,3); my %h=(k=>"v"); print "@a[0,1] $a[-1] $h{k} @h{'k'} $#a ${\ scalar(@a)} @{[ map { $_*2 } @a ]}\n";
