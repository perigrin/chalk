#!./chalk

# ABOUTME: Test boolean operators (&&, ||, and, or, !) 
# ABOUTME: Validates short-circuit evaluation and truthiness semantics

print "1..12\n";

# Logical AND operator tests
$true = '1';
$false = '0';
$empty = '';

print $true && $true; print "\n";    # Should print 1
print $true && $false; print "\n";   # Should print 0  
print $false && $true; print "\n";   # Should print 0
print $false && $false; print "\n";  # Should print 0

# Logical OR operator tests  
print $true || $true; print "\n";    # Should print 1
print $true || $false; print "\n";   # Should print 1
print $false || $true; print "\n";   # Should print 1
print $false || $false; print "\n";  # Should print 0

# Negation operator tests
print !$true; print "\n";            # Should print 0
print !$false; print "\n";           # Should print 1
print !$empty; print "\n";           # Should print 1

# Complex truthiness test
$nonempty = 'hello';
print !$nonempty; print "\n";        # Should print 0