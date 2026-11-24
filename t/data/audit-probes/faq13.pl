my $s="aXb"; $s=~/X/; my ($pre,$m,$post)=($`,$&,$'); print "$pre$m$post\n";
