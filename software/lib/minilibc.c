#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t count)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    size_t i;

    for (i = 0; i < count; i++)
        d[i] = s[i];
    return dst;
}

void *memmove(void *dst, const void *src, size_t count)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    if (d < s) {
        size_t i;
        for (i = 0; i < count; i++)
            d[i] = s[i];
    } else if (d > s) {
        while (count != 0u) {
            count--;
            d[count] = s[count];
        }
    }
    return dst;
}

void *memset(void *dst, int value, size_t count)
{
    unsigned char *d = (unsigned char *)dst;
    size_t i;

    for (i = 0; i < count; i++)
        d[i] = (unsigned char)value;
    return dst;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    size_t i;

    for (i = 0; i < count; i++) {
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
    }
    return 0;
}

size_t strlen(const char *text)
{
    size_t length = 0u;
    while (text[length] != '\0')
        length++;
    return length;
}
