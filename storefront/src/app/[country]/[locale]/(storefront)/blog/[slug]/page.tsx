import type { Metadata } from "next";
import Image from "next/image";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { getPost } from "@/lib/data/posts";
import { getStoreName } from "@/lib/store";

interface BlogPostPageProps {
  params: Promise<{
    country: string;
    locale: string;
    slug: string;
  }>;
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

export async function generateMetadata({
  params,
}: BlogPostPageProps): Promise<Metadata> {
  const { slug, locale } = await params;
  const post = await getPost(slug);

  const storeName = getStoreName();

  if (!post) {
    const t = await getTranslations({
      locale: locale as Locale,
      namespace: "blog",
    });
    return {
      title: t("notFound"),
    };
  }

  const title =
    post.seo_title || `${post.title}${storeName ? ` | ${storeName}` : ""}`;
  const description = post.seo_description || post.excerpt || undefined;

  return {
    title,
    description,
    openGraph: {
      title: post.title,
      description: description ?? undefined,
      images: post.cover_image_url
        ? [{ url: post.cover_image_url }]
        : undefined,
      type: "article",
      publishedTime: post.published_at ?? undefined,
    },
  };
}

export default async function BlogPostPage({
  params,
}: BlogPostPageProps): Promise<React.JSX.Element> {
  const { slug, locale } = await params;
  const [post, t] = await Promise.all([
    getPost(slug),
    getTranslations({ locale: locale as Locale, namespace: "blog" }),
  ]);

  if (!post) {
    notFound();
  }

  const publishedDate = formatDate(post.published_at);

  return (
    <article className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <header className="mb-8">
        {publishedDate ? (
          <time
            dateTime={post.published_at ?? undefined}
            className="text-sm text-gray-500"
          >
            {publishedDate}
          </time>
        ) : null}
        <h1 className="mt-2 text-4xl font-bold text-gray-900">{post.title}</h1>
        {post.author ? (
          <p className="mt-3 text-gray-600">By {post.author}</p>
        ) : null}
      </header>

      {post.cover_image_url ? (
        <div className="relative aspect-[16/9] overflow-hidden rounded-lg bg-gray-100 mb-8">
          <Image
            src={post.cover_image_url}
            alt={post.title}
            fill
            sizes="(min-width: 768px) 768px, 100vw"
            className="object-cover"
            priority
          />
        </div>
      ) : null}

      {post.body_html ? (
        <div
          className="prose prose-gray max-w-none"
          dangerouslySetInnerHTML={{ __html: post.body_html }}
        />
      ) : post.body ? (
        <div className="prose prose-gray max-w-none whitespace-pre-wrap">
          {post.body}
        </div>
      ) : (
        <p className="text-gray-500">{t("noContent")}</p>
      )}

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "Article",
            headline: post.title,
            description: post.excerpt ?? undefined,
            image: post.cover_image_url ?? undefined,
            author: post.author
              ? { "@type": "Person", name: post.author }
              : undefined,
            datePublished: post.published_at ?? undefined,
            dateModified: post.published_at ?? undefined,
          }),
        }}
      />
    </article>
  );
}
