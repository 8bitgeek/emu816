#include <stdio.h>
#include <stdint.h>

uint32_t j;

int main()
{
	for(j=0; j < 0xffff; j++)
		printf("%04x\r",j);
	printf("\n");
	return 0;
}

