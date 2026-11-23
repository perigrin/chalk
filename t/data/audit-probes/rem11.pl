my %reg; sub reg { my ($k,$v)=@_; $reg{$k}=$v } sub get { $reg{$_[0]} } reg("a",1); my $x=get("a"); reg("a",2); print $x,get("a"),"\n";
