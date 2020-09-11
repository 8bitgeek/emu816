#include <stdio.h>

unsigned int j;

int main()
{
	for(j=0; j < 0xffff; j++)
		printf("%04x\r",j);
	printf("\n");
	return 0;
}

