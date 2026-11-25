my $s=sprintf "%s-%s", "a", "b"; my @l=("c","d"); my $t=sprintf "%s-%s", @l; my $u=sprintf("%d items", scalar(@l)); print "$s $t $u\n";
