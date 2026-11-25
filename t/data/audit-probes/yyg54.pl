my $s="hello"; { no warnings; my $o = substr($s,9); print defined $o ? "d" : "u"; } substr($s,0,1)="J"; substr($s,-1,1,"y"); print "$s\n";
