print "1..12\n";
$true = '1';
$false = '0';
$empty = '';

print $true && $true; print "\n";
print $true && $false; print "\n";
print $false && $true; print "\n";
print $false && $false; print "\n";
print $true || $true; print "\n";
print $true || $false; print "\n";
print $false || $true; print "\n";
print $false || $false; print "\n";
print !$true; print "\n";
print !$false; print "\n";
print !$empty; print "\n";
$nonempty = 'hello';
print !$nonempty; print "\n";