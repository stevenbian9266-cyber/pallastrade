import type { Post } from "@pallastrade/sdk";
import Image from "next/image";

interface PostCardProps {
  post: Post;
}

function formatDate(dateString: string | null): string | null {
  if (!dateString) return null;
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

export function PostCard({ post }: PostCardProps) {
  const publishedDate = formatDate(post.published_at);

  return (
    <article className="flex flex-col overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm transition-shadow group-hover:shadow-md">
      {post.cover_image_url ? (
        <div className="relative aspect-[16/9] overflow-hidden bg-gray-100">
          <Image
            src={post.cover_image_url}
            alt={post.title}
            fill
            sizes="(min-width: 1024px) 33vw, (min-width: 768px) 50vw, 100vw"
            className="object-cover transition-transform duration-300 group-hover:scale-105"
          />
        </div>
      ) : (
        <div className="relative aspect-[16/9] bg-gray-100" />
      )}

      <div className="flex flex-1 flex-col p-6">
        {publishedDate ? (
          <time
            dateTime={post.published_at ?? undefined}
            className="text-sm text-gray-500"
          >
            {publishedDate}
          </time>
        ) : null}
        <h3 className="mt-2 text-xl font-semibold text-gray-900 group-hover:text-primary transition-colors">
          {post.title}
        </h3>
        {post.excerpt ? (
          <p className="mt-3 line-clamp-3 text-gray-600">{post.excerpt}</p>
        ) : null}
        {post.author ? (
          <p className="mt-4 text-sm text-gray-500">By {post.author}</p>
        ) : null}
      </div>
    </article>
  );
}
