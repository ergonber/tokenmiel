export function buildApiUrl(baseUrl: string, path: string): string {
  if (!baseUrl) {
    return path;
  }

  return new URL(path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`).toString();
}

export async function fetchApiJson<T>(path: string, baseUrl = process.env.NEXT_PUBLIC_API_BASE_URL ?? ''): Promise<T> {
  const response = await fetch(buildApiUrl(baseUrl, path), {
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Request failed with status ${response.status}`);
  }

  return (await response.json()) as T;
}
